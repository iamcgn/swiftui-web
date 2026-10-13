// The browser behind UserNotifications (decision 0021, pf-usernotifications): the page's
// Notification API — the user's permission as the browser holds it, `requestPermission()` as
// the one prompt, `new Notification(title, {body, tag})` for a delivered local request, and its
// `click` as the response the delegate receives. Nothing is pushed from a server: there is no
// push service here, and `UIApplication.registerForRemoteNotifications` fails through the
// app's delegate (UIKitWeb).
#if os(WASI)
import JavaScriptKit
import UserNotifications

@MainActor
enum NotificationsHost {
    static func install() {
        guard let constructor = JSObject.global.Notification.function else { return }   // not every browser (iOS Safari outside a web app)
        _UserNotificationsHost.permission = { status(of: constructor.permission.string) }
        _UserNotificationsHost.requestPermission = { completion in
            guard let promise = constructor.requestPermission?().object else { completion(.denied); return }
            let resolved = JSClosure { (arguments: [JSValue]) -> JSValue in
                let answer = status(of: arguments.first?.string)
                MainActor.assumeIsolated { completion(answer) }
                return .undefined
            }
            let rejected = JSClosure { (_: [JSValue]) -> JSValue in MainActor.assumeIsolated { completion(.denied) }; return .undefined }
            _ = promise.then!(resolved, rejected)
            retained.append(resolved)
            retained.append(rejected)
        }
        _UserNotificationsHost.show = { title, body, identifier, onClick in
            let options = JSObject.global.Object.function!.new()
            options.body = .string(body)
            options.tag = .string(identifier)
            let notification = constructor.new(title, options)
            let clicked = JSClosure { (_: [JSValue]) -> JSValue in MainActor.assumeIsolated { onClick() }; return .undefined }
            notification.onclick = .object(clicked)
            retained.append(clicked)
            shown.append(notification)
        }
    }

    nonisolated static func status(of permission: String?) -> UNAuthorizationStatus {
        switch permission {
        case "granted": .authorized
        case "denied": .denied
        default: .notDetermined
        }
    }

    nonisolated(unsafe) static var retained: [JSClosure] = []
    nonisolated(unsafe) static var shown: [JSObject] = []
}
#endif
