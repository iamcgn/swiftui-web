// The browser behind CoreMotion: the `devicemotion` and `deviceorientation` events, merged into
// one reading per event (the latest orientation rides along with each motion event). Safari on
// iOS asks the person before it sends motion events, and only from a tap: the host asks when
// updates start and, if the browser wants a tap first, again on the next one. A browser counts
// as having sensors when it has motion events and a touch screen.
#if os(WASI)
import CoreMotionHost
import JavaScriptKit

@MainActor
enum MotionHost {
    nonisolated(unsafe) static var retained: [JSClosure] = []

    private static let sensors: Bool = {
        guard let make = JSObject.global.Function.function,
              let test = try? make.throws.new("return typeof DeviceMotionEvent !== 'undefined' && (navigator.maxTouchPoints || 0) > 0;")
        else { return false }
        return test().boolean ?? false
    }()

    /// `(report)` → the stop function: listens for both events and calls `report` with a flat
    /// array of 13 numbers (null where the browser gave none): acceleration with gravity,
    /// acceleration, rotation rate, orientation, then the time in seconds.
    private static let listen: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var o = null;
        var v = function (x) { return (typeof x === 'number') ? x : null; };
        var xyz = function (a) { return a ? [v(a.x), v(a.y), v(a.z)] : [null, null, null]; };
        var abg = function (a) { return a ? [v(a.alpha), v(a.beta), v(a.gamma)] : [null, null, null]; };
        var send = function (m) {
          var r = [].concat(xyz(m && m.accelerationIncludingGravity), xyz(m && m.acceleration), abg(m && m.rotationRate),
                            o || [null, null, null], [performance.now() / 1000]);
          report(r);
        };
        var moved = false;
        var onMotion = function (e) { moved = true; send(e); };
        var onTurn = function (e) { o = [v(e.alpha), v(e.beta), v(e.gamma)]; if (!moved) send(null); };
        var listen = function () { window.addEventListener('devicemotion', onMotion); window.addEventListener('deviceorientation', onTurn); };
        var ask = window.DeviceMotionEvent && DeviceMotionEvent.requestPermission;
        if (ask) {
          var retry = function () { document.removeEventListener('pointerup', retry, true);
            DeviceMotionEvent.requestPermission().then(function (s) { if (s === 'granted') listen(); }, function () {}); };
          DeviceMotionEvent.requestPermission().then(function (s) { if (s === 'granted') listen(); },
            function () { document.addEventListener('pointerup', retry, true); });
        } else { listen(); }
        return function () {
          window.removeEventListener('devicemotion', onMotion);
          window.removeEventListener('deviceorientation', onTurn);
        };
        """
        return try? make.throws.new("report", body)
    }()

    static func install() {
        _CoreMotionHost.available = { sensors }
        _CoreMotionHost.start = { deliver in
            guard let listen else { return {} }
            let report = JSClosure { (arguments: [JSValue]) -> JSValue in
                guard let flat = arguments.first?.object else { return .undefined }
                let n = (0..<13).map { flat[$0].number }
                func triple(_ i: Int) -> (Double, Double, Double)? {
                    guard let a = n[i], let b = n[i + 1], let c = n[i + 2] else { return nil }
                    return (a, b, c)
                }
                let withGravity = triple(0).map { (x: $0.0, y: $0.1, z: $0.2) }
                let moving = triple(3).map { (x: $0.0, y: $0.1, z: $0.2) }
                let rate = triple(6).map { (alpha: $0.0, beta: $0.1, gamma: $0.2) }
                // The compass heading can be missing while the tilt is known.
                let orientation = (n[10] != nil && n[11] != nil) ? (alpha: n[9] ?? 0, beta: n[10]!, gamma: n[11]!) : nil
                let sample = _CoreMotionHost.Sample(accelerationIncludingGravity: withGravity, acceleration: moving,
                                                    rotationRate: rate, orientation: orientation, timestamp: n[12] ?? 0)
                MainActor.assumeIsolated { deliver(sample) }
                return .undefined
            }
            retained.append(report)
            let stop = listen(report).object
            return { _ = stop?.callAsFunction() }
        }
    }
}
#endif
