// The browser behind CoreLocation (pf-corelocation): `navigator.geolocation` for one position
// (`getCurrentPosition`, which prompts the first time) and for positions as they change
// (`watchPosition`, `clearWatch`), and the Permissions API for the browser's answer, read once at
// launch and again whenever it changes. A browser without the Permissions API still works: the
// manager learns the answer from the first position or refusal.
#if os(WASI)
import CoreLocationHost
import JavaScriptKit

@MainActor
enum GeolocationHost {
    static func install() {
        guard let geolocation = JSObject.global.navigator.geolocation.object else { return }
        _CoreLocationHost.permission = { state }
        _CoreLocationHost.locate = { highAccuracy, completion in
            let (success, failure) = callbacks(completion)
            _ = geolocation.getCurrentPosition!(success, failure, options(highAccuracy))
            retained.append(success)
            retained.append(failure)
        }
        _CoreLocationHost.watch = { highAccuracy, update in
            let (success, failure) = callbacks(update)
            let id = Int(geolocation.watchPosition!(success, failure, options(highAccuracy)).number ?? -1)
            watches[id] = [success, failure]
            return id
        }
        _CoreLocationHost.clearWatch = { id in
            _ = geolocation.clearWatch!(id)
            watches[id] = nil
        }
        readPermission()
    }

    /// The Permissions API's state for geolocation: "granted", "denied" or "prompt".
    nonisolated(unsafe) static var state: String?
    nonisolated(unsafe) static var retained: [JSClosure] = []
    nonisolated(unsafe) static var watches: [Int: [JSClosure]] = [:]

    private static func readPermission() {
        guard let permissions = JSObject.global.navigator.permissions.object else { return }
        let descriptor = JSObject.global.Object.function!.new()
        descriptor.name = .string("geolocation")
        guard let promise = permissions.query?(descriptor).object else { return }
        let changed = JSClosure { (arguments: [JSValue]) -> JSValue in
            let next = arguments.first?.object?.target.object?.state.string
            MainActor.assumeIsolated {
                state = next
                _CoreLocationHost.permissionDidChange()
            }
            return .undefined
        }
        let resolved = JSClosure { (arguments: [JSValue]) -> JSValue in
            guard let status = arguments.first?.object else { return .undefined }
            let first = status.state.string
            status.onchange = .object(changed)
            MainActor.assumeIsolated {
                state = first
                _CoreLocationHost.permissionDidChange()
            }
            return .undefined
        }
        let rejected = JSClosure { (_: [JSValue]) -> JSValue in .undefined }   // Safari before 16: no geolocation in the Permissions API
        _ = promise.then!(resolved, rejected)
        retained += [changed, resolved, rejected]
    }

    private static func options(_ highAccuracy: Bool) -> JSObject {
        let options = JSObject.global.Object.function!.new()
        options.enableHighAccuracy = .boolean(highAccuracy)
        return options
    }

    private static func callbacks(_ deliver: @escaping _CoreLocationHost.Update) -> (JSClosure, JSClosure) {
        let success = JSClosure { (arguments: [JSValue]) -> JSValue in
            let position = arguments.first.flatMap(position(from:))
            MainActor.assumeIsolated { deliver(position.map { .success($0) } ?? .failure(.unavailable)) }
            return .undefined
        }
        let failure = JSClosure { (arguments: [JSValue]) -> JSValue in
            let code = Int(arguments.first?.object?.code.number ?? 2)
            MainActor.assumeIsolated { deliver(.failure(_CoreLocationHost.Failure(rawValue: code) ?? .unavailable)) }
            return .undefined
        }
        return (success, failure)
    }

    nonisolated private static func position(from value: JSValue) -> _CoreLocationHost.Position? {
        guard let position = value.object, let coords = position.coords.object,
              let latitude = coords.latitude.number, let longitude = coords.longitude.number else { return nil }
        return _CoreLocationHost.Position(latitude: latitude, longitude: longitude, accuracy: coords.accuracy.number ?? -1,
                                          altitude: coords.altitude.number, altitudeAccuracy: coords.altitudeAccuracy.number,
                                          heading: coords.heading.number, speed: coords.speed.number,
                                          timestamp: position.timestamp.number ?? 0)
    }
}
#endif
