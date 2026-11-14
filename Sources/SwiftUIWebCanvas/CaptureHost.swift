// The browser behind AVFoundation's camera (AVCaptureHost, AVCapture.swift): `getUserMedia` with
// the facing the device asks for, a hidden `<video>` playing the stream, and from it frames (a
// canvas's pixels, swapped to BGRA), stills (JPEG from the canvas, with the pixels), codes
// (`BarcodeDetector`, where the browser has it) and movies (`MediaRecorder`). The stream is kept
// in `globalThis.__swiftuiWebCapture[session]`, where CanvasHost's camera elements find it for
// the preview. At launch the host counts the cameras and microphones (`enumerateDevices`, which
// asks the person nothing) and reads the camera permission where the browser says it. A movie's
// frames, for the image generator, come from another hidden `<video>` loading the movie's URL,
// seeked to the asked time and drawn to a canvas at the asked size.
#if os(WASI)
import AVCaptureHost
import JavaScriptKit

@MainActor
enum CaptureHost {
    nonisolated(unsafe) static var retained: [JSClosure] = []

    /// The helpers, one object of functions over the registry.
    private static let helpers: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var md = navigator.mediaDevices;
        var reg = globalThis.__swiftuiWebCapture = globalThis.__swiftuiWebCapture || {};
        var stopTracks = function (s) { if (s) s.getTracks().forEach(function (t) { t.stop(); }); };
        var track = function (e) { return e.stream ? e.stream.getVideoTracks()[0] : null; };
        var apply = function (e, c) { var t = track(e); if (t && t.applyConstraints) t.applyConstraints({ advanced: [c] }).catch(function () {}); };
        var caps = function (e) { var t = track(e); return (t && t.getCapabilities) ? t.getCapabilities() : {}; };
        return {
          supported: function () { return !!(md && md.getUserMedia); },
          probe: function (report) {
            var cams = -1, mics = -1, state = '', formats = [], left = 3;
            var done = function () { if (--left === 0) report(cams, mics, state, formats); };
            md.enumerateDevices().then(function (list) {
              cams = list.filter(function (d) { return d.kind === 'videoinput'; }).length;
              mics = list.filter(function (d) { return d.kind === 'audioinput'; }).length; done();
            }, done);
            if (navigator.permissions && navigator.permissions.query) {
              navigator.permissions.query({ name: 'camera' }).then(function (p) { state = p.state; done(); }, done);
            } else { done(); }
            if (globalThis.BarcodeDetector && BarcodeDetector.getSupportedFormats) {
              BarcodeDetector.getSupportedFormats().then(function (f) { formats = f; done(); }, done);
            } else { done(); }
          },
          request: function (video, done) {
            md.getUserMedia(video ? { video: true } : { audio: true })
              .then(function (s) { stopTracks(s); done(true); }, function () { done(false); });
          },
          open: function (id, facing, width, audio, started) {
            var e = { id: id, stopped: false, stream: null, video: null, timers: {} };
            var video = { width: { ideal: width } };
            if (facing) video.facingMode = { ideal: facing };
            md.getUserMedia({ video: video, audio: !!audio }).then(function (stream) {
              if (e.stopped) { stopTracks(stream); return; }
              e.stream = stream;
              var v = document.createElement('video');
              v.muted = true; v.playsInline = true; v.setAttribute('playsinline', ''); v.autoplay = true;
              v.srcObject = stream; e.video = v;
              var ready = function () {
                if (e.stopped || e.live) return;
                e.live = true;
                reg[id] = e;
                var c = caps(e);
                var zoom = c.zoom && c.zoom.max ? c.zoom.max / (c.zoom.min || 1) : 1;
                started([v.videoWidth, v.videoHeight, !!c.torch, zoom], '');
              };
              v.addEventListener('loadedmetadata', ready);
              var p = v.play(); if (p && p.catch) p.catch(function () {});
              if (v.readyState >= 1) ready();
            }, function (err) { if (!e.stopped) started(null, (err && err.name) || 'Error'); });
            return e;
          },
          stop: function (e) {
            e.stopped = true;
            Object.keys(e.timers).forEach(function (k) { clearInterval(e.timers[k]); });
            if (e.recorder && e.recorder.state !== 'inactive') e.recorder.stop();
            stopTracks(e.stream);
            if (e.video) e.video.srcObject = null;
            if (reg[e.id] === e) delete reg[e.id];
          },
          frames: function (e, maxWidth, fps, deliver) {
            clearInterval(e.timers.frames); delete e.timers.frames;
            if (!deliver) return;
            var canvas = document.createElement('canvas'), g = canvas.getContext('2d', { willReadFrequently: true });
            e.timers.frames = setInterval(function () {
              var v = e.video;
              if (!v || v.readyState < 2 || !v.videoWidth) return;
              var w = Math.min(v.videoWidth, maxWidth), h = Math.round(v.videoHeight * w / v.videoWidth);
              if (canvas.width !== w) canvas.width = w;
              if (canvas.height !== h) canvas.height = h;
              g.drawImage(v, 0, 0, w, h);
              var d = new Uint8Array(g.getImageData(0, 0, w, h).data.buffer);
              for (var i = 0; i < d.length; i += 4) { var r = d[i]; d[i] = d[i + 2]; d[i + 2] = r; }
              deliver(w, h, d, performance.now() / 1000);
            }, 1000 / Math.max(fps, 1));
          },
          photo: function (e, done) {
            var v = e.video;
            if (!v || !v.videoWidth) { done(null, 0, 0, null); return; }
            var w = v.videoWidth, h = v.videoHeight;
            var canvas = document.createElement('canvas'); canvas.width = w; canvas.height = h;
            var g = canvas.getContext('2d'); g.drawImage(v, 0, 0, w, h);
            var px = new Uint8Array(g.getImageData(0, 0, w, h).data.buffer);
            canvas.toBlob(function (b) {
              if (!b) { done(null, w, h, px); return; }
              b.arrayBuffer().then(function (buf) { done(new Uint8Array(buf), w, h, px); }, function () { done(null, w, h, px); });
            }, 'image/jpeg', 0.92);
          },
          codes: function (e, formats, deliver) {
            clearInterval(e.timers.codes); delete e.timers.codes;
            if (!deliver || !globalThis.BarcodeDetector || !formats.length) return;
            var detector; try { detector = new BarcodeDetector({ formats: formats }); } catch (x) { return; }
            var busy = false;
            e.timers.codes = setInterval(function () {
              var v = e.video;
              if (busy || !v || v.readyState < 2 || !v.videoWidth) return;
              busy = true;
              detector.detect(v).then(function (found) {
                busy = false;
                if (e.stopped || !found.length) return;
                var w = v.videoWidth, h = v.videoHeight;
                deliver(found.map(function (c) {
                  var pts = [];
                  (c.cornerPoints || []).forEach(function (p) { pts.push(p.x / w, p.y / h); });
                  return [c.format, c.rawValue, pts];
                }));
              }, function () { busy = false; });
            }, 250);
          },
          torch: function (e, on) { apply(e, { torch: !!on }); },
          zoom: function (e, factor) { var z = caps(e).zoom; if (z) apply(e, { zoom: Math.min(z.max, (z.min || 1) * factor) }); },
          point: function (e, x, y) { apply(e, { pointsOfInterest: [{ x: x, y: y }] }); },
          record: function (e) {
            if (!e.stream || !globalThis.MediaRecorder) return;
            e.chunks = [];
            try { e.recorder = new MediaRecorder(e.stream); } catch (x) { e.recorder = null; return; }
            e.recorder.ondataavailable = function (ev) { if (ev.data && ev.data.size) e.chunks.push(ev.data); };
            e.recorder.start();
          },
          stopRecording: function (e, done) {
            var r = e.recorder;
            if (!r || r.state === 'inactive') { done(null, ''); return; }
            r.onstop = function () {
              var blob = new Blob(e.chunks || [], { type: r.mimeType });
              e.recorder = null; e.chunks = [];
              blob.arrayBuffer().then(function (buf) { done(new Uint8Array(buf), r.mimeType || ''); }, function () { done(null, ''); });
            };
            r.stop();
          },
          movieFrame: function (url, t, mw, mh, done) {
            var v = document.createElement('video'), settled = false;
            v.muted = true; v.playsInline = true; v.preload = 'auto'; v.crossOrigin = 'anonymous';
            var finish = function (w, h, px, at) {
              if (settled) return;
              settled = true; clearTimeout(timer); v.removeAttribute('src'); v.load(); done(w, h, px, at);
            };
            var fail = function () { finish(0, 0, null, 0); };
            var timer = setTimeout(fail, 20000);
            var draw = function () {
              try {
                var w = v.videoWidth, h = v.videoHeight, s = 1;
                if (!w || !h) { fail(); return; }
                if (mw > 0) s = Math.min(s, mw / w);
                if (mh > 0) s = Math.min(s, mh / h);
                w = Math.max(1, Math.round(w * s)); h = Math.max(1, Math.round(h * s));
                var c = document.createElement('canvas'); c.width = w; c.height = h;
                var g = c.getContext('2d'); g.drawImage(v, 0, 0, w, h);
                finish(w, h, new Uint8Array(g.getImageData(0, 0, w, h).data.buffer), v.currentTime);
              } catch (x) { fail(); }
            };
            v.addEventListener('error', fail);
            v.addEventListener('loadeddata', function () {
              var d = v.duration, at = Math.max(0, isFinite(d) ? Math.min(t, Math.max(0, d - 0.001)) : t);
              if (Math.abs(v.currentTime - at) < 0.001) { draw(); return; }
              v.addEventListener('seeked', draw, { once: true });
              v.currentTime = at;
            }, { once: true });
            v.src = url;
          }
        };
        """
        guard let factory = try? make.throws.new(body) else { return nil }
        return factory().object
    }()

    static func install() {
        guard let js = helpers else { return }
        // A movie's frames, for AVFoundation's image generator: any browser that plays video.
        _AVFrameHost.frame = { url, seconds, maxWidth, maxHeight, done in
            let report = JSClosure { (arguments: [JSValue]) -> JSValue in
                let width = Int(arguments[0].number ?? 0), height = Int(arguments[1].number ?? 0)
                let pixels = CaptureStream.bytes(arguments[2])
                let frame = width > 0 && height > 0 && !pixels.isEmpty
                    ? _AVFrame(width: width, height: height, rgba: pixels, seconds: arguments[3].number ?? seconds) : nil
                MainActor.assumeIsolated { done(frame) }
                return .undefined
            }
            retained.append(report)
            _ = js.movieFrame!(url, seconds, maxWidth, maxHeight, report)
        }
        guard js.supported!().boolean == true else { return }
        // There may be a camera until the browser has said.
        _AVCaptureHost.cameraCount = -1
        _AVCaptureHost.microphoneCount = -1
        let report = JSClosure { (arguments: [JSValue]) -> JSValue in
            let cameras = arguments[0].number.map(Int.init) ?? -1
            let microphones = arguments[1].number.map(Int.init) ?? -1
            let state = arguments[2].string ?? ""
            var formats: [String] = []
            if let list = arguments[3].object, let count = list.length.number {
                formats = (0..<Int(count)).compactMap { list[$0].string }
            }
            MainActor.assumeIsolated {
                _AVCaptureHost.cameraCount = cameras
                _AVCaptureHost.microphoneCount = microphones
                _AVCaptureHost.codeFormats = formats
                if state == "granted" { _AVCaptureHost.videoAuthorization = 3 }
                if state == "denied" { _AVCaptureHost.videoAuthorization = 2 }
            }
            return .undefined
        }
        retained.append(report)
        _ = js.probe!(report)

        _AVCaptureHost.requestAccess = { video, completion in
            let done = JSClosure { (arguments: [JSValue]) -> JSValue in
                let granted = arguments.first?.boolean ?? false
                MainActor.assumeIsolated { completion(granted) }
                return .undefined
            }
            retained.append(done)
            _ = js.request!(video, done)
        }

        _AVCaptureHost.open = { session, facing, width, audio, started in
            let report = JSClosure { (arguments: [JSValue]) -> JSValue in
                var value: _AVCaptureStarted?
                if let info = arguments.first?.object {
                    value = _AVCaptureStarted(width: Int(info[0].number ?? 0), height: Int(info[1].number ?? 0),
                                              hasTorch: info[2].boolean ?? false, maxZoom: max(info[3].number ?? 1, 1))
                }
                let refused = arguments.count > 1 && arguments[1].string == "NotAllowedError"
                MainActor.assumeIsolated {
                    if refused { _AVCaptureHost.videoAuthorization = 2 }
                    started(value)
                }
                return .undefined
            }
            retained.append(report)
            guard let entry = js.open!(session, facing.rawValue, width, audio, report).object else { return nil }
            return CaptureStream(js: js, entry: entry)
        }
    }
}

/// One open camera: the registry entry the helpers keep its stream, video element and timers in.
final class CaptureStream: _AVCaptureStream {
    private let js: JSObject
    private let entry: JSObject

    init(js: JSObject, entry: JSObject) {
        self.js = js
        self.entry = entry
    }

    static func bytes(_ value: JSValue) -> [UInt8] {
        guard let array = value.object else { return [] }
        return JSTypedArray<UInt8>(unsafelyWrapping: array).withUnsafeBytes { Array($0) }
    }

    private static func keep(_ closure: JSClosure) -> JSClosure {
        CaptureHost.retained.append(closure)
        return closure
    }

    func stop() { _ = js.stop!(entry) }

    func deliverFrames(maxWidth: Int, fps: Double, _ deliver: (@MainActor (Int, Int, [UInt8], Double) -> Void)?) {
        guard let deliver else { _ = js.frames!(entry, maxWidth, fps, JSValue.null); return }
        let closure = Self.keep(JSClosure { (arguments: [JSValue]) -> JSValue in
            let width = Int(arguments[0].number ?? 0), height = Int(arguments[1].number ?? 0)
            let pixels = Self.bytes(arguments[2])
            let time = arguments[3].number ?? 0
            MainActor.assumeIsolated { deliver(width, height, pixels, time) }
            return .undefined
        })
        _ = js.frames!(entry, maxWidth, fps, closure)
    }

    func takePhoto(_ completion: @escaping @MainActor ([UInt8], Int, Int, [UInt8]) -> Void) {
        let closure = Self.keep(JSClosure { (arguments: [JSValue]) -> JSValue in
            let jpeg = Self.bytes(arguments[0])
            let width = Int(arguments[1].number ?? 0), height = Int(arguments[2].number ?? 0)
            let pixels = Self.bytes(arguments[3])
            MainActor.assumeIsolated { completion(jpeg, width, height, pixels) }
            return .undefined
        })
        _ = js.photo!(entry, closure)
    }

    func detectCodes(formats: [String], _ deliver: (@MainActor ([_AVCaptureCode]) -> Void)?) {
        let list = JSObject.global.Array.function!.new()
        for (index, format) in formats.enumerated() { list[index] = .string(format) }
        guard let deliver else { _ = js.codes!(entry, list, JSValue.null); return }
        let closure = Self.keep(JSClosure { (arguments: [JSValue]) -> JSValue in
            guard let found = arguments.first?.object, let count = found.length.number else { return .undefined }
            var codes: [_AVCaptureCode] = []
            for index in 0..<Int(count) {
                guard let code = found[index].object else { continue }
                var corners: [Double] = []
                if let points = code[2].object, let n = points.length.number {
                    corners = (0..<Int(n)).map { points[$0].number ?? 0 }
                }
                codes.append(_AVCaptureCode(format: code[0].string ?? "", value: code[1].string ?? "", corners: corners))
            }
            MainActor.assumeIsolated { deliver(codes) }
            return .undefined
        })
        _ = js.codes!(entry, list, closure)
    }

    func setTorch(_ on: Bool, level: Double) { _ = js.torch!(entry, on) }
    func setZoom(_ factor: Double) { _ = js.zoom!(entry, factor) }
    func setPointOfInterest(x: Double, y: Double) { _ = js.point!(entry, x, y) }
    func startRecording() { _ = js.record!(entry) }

    func stopRecording(_ completion: @escaping @MainActor ([UInt8], String) -> Void) {
        let closure = Self.keep(JSClosure { (arguments: [JSValue]) -> JSValue in
            let data = Self.bytes(arguments[0])
            let type = arguments.count > 1 ? arguments[1].string ?? "" : ""
            MainActor.assumeIsolated { completion(data, type) }
            return .undefined
        })
        _ = js.stopRecording!(entry, closure)
    }
}
#endif
