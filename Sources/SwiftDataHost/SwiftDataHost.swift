// The browser's storage as SwiftData's stores read it (decision 0021, pf-swiftdata): the hook
// SwiftUIWebCanvas installs (DataHost.swift) and SwiftData uses as `_ModelStore.Host`. A module
// of its own, depending on nothing, so installing the hook links only this into an app that
// never opens a model container (decision 0006).

public enum _SwiftDataHost {
    /// Loads and saves one store's JSON by name (the browser host: localStorage).
    nonisolated(unsafe) public static var store: (load: (String) throws -> String?, save: (String, String?) throws -> Void)?
}
