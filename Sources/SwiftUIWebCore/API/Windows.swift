// Window management: `openWindow`, `dismissWindow` and `openSettings` open the app's window
// scenes as floating windows inside the host (a title bar with traffic lights over the content,
// cascaded, non-modal), so every host has them and state stays shared.

/// Opens a window scene (`EnvironmentValues.openWindow`).
public struct OpenWindowAction {
    package let open: @MainActor (String?, Any?) -> Void
    package init(_ open: @escaping @MainActor (String?, Any?) -> Void) { self.open = open }

    @MainActor public func callAsFunction(id: String) { open(id, nil) }
    @MainActor public func callAsFunction<D: Codable & Hashable>(value: D) { open(nil, value) }
    @MainActor public func callAsFunction<D: Codable & Hashable>(id: String, value: D) { open(id, value) }
}

/// Closes a window (`EnvironmentValues.dismissWindow`): the current one, or by id and value.
public struct DismissWindowAction {
    package let dismiss: @MainActor (String?, Any?, Bool) -> Void
    package init(_ dismiss: @escaping @MainActor (String?, Any?, Bool) -> Void) { self.dismiss = dismiss }

    @MainActor public func callAsFunction() { dismiss(nil, nil, true) }
    @MainActor public func callAsFunction(id: String) { dismiss(id, nil, false) }
    @MainActor public func callAsFunction<D: Codable & Hashable>(value: D) { dismiss(nil, value, false) }
    @MainActor public func callAsFunction<D: Codable & Hashable>(id: String, value: D) { dismiss(id, value, false) }
}

/// Opens the settings window (`EnvironmentValues.openSettings`).
public struct OpenSettingsAction {
    package let open: @MainActor () -> Void
    package init(_ open: @escaping @MainActor () -> Void) { self.open = open }
    @MainActor public func callAsFunction() { open() }
}

package struct OpenWindowKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue = OpenWindowAction { _, _ in }
}
package struct DismissWindowKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue = DismissWindowAction { _, _, _ in }
}
package struct OpenSettingsKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue = OpenSettingsAction {}
}
package struct WindowIdentityKey: EnvironmentKey {
    package static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    public var openWindow: OpenWindowAction {
        get { self[OpenWindowKey.self] }
        set { self[OpenWindowKey.self] = newValue }
    }
    public var dismissWindow: DismissWindowAction {
        get { self[DismissWindowKey.self] }
        set { self[DismissWindowKey.self] = newValue }
    }
    public var openSettings: OpenSettingsAction {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
    /// Whether the host can show more than one window (always: windows float inside it).
    public var supportsMultipleWindows: Bool { true }
    /// The window this environment belongs to (nil in the main window).
    package var _windowIdentity: Int? {
        get { self[WindowIdentityKey.self] }
        set { self[WindowIdentityKey.self] = newValue }
    }
}
