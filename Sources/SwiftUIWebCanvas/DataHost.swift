// The browser behind SwiftData's stores (decision 0021, pf-swiftdata): a container that is not
// in-memory-only keeps its rows in localStorage under `swiftuiweb.swiftdata.<name>` — one JSON
// document per store, written at every save, read when a container of that name opens. The
// page's origin bounds it as it bounds every localStorage key. A browser without localStorage
// binds nothing, and a persistent container then fails to open (`storageUnavailable`) — the
// app sees the failure as it would an unwritable store on a device; a full quota fails the save.
#if os(WASI)
import JavaScriptKit
import SwiftData

@MainActor
enum DataHost {
    static let prefix = "swiftuiweb.swiftdata."

    static func install() {
        guard let storage = JSObject.global.localStorage.object else { return }
        _ModelStore.Host.store = (
            load: { name in storage.getItem?(prefix + name).string },
            // `setItem` throws when the origin's quota is spent (QuotaExceededError): the save's error.
            save: { name, json in
                if let json { try storage.setItem.function!.throws(this: storage, prefix + name, json) }
                else { _ = storage.removeItem?(prefix + name) }
            }
        )
    }
}
#endif
