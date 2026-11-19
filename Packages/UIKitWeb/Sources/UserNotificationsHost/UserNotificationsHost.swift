// The browser's Notification API as UserNotifications reads it (decision 0021,
// pf-usernotifications): the hook SwiftUIWebCanvas installs (NotificationsHost.swift) and
// UserNotifications uses. A module of its own, depending on nothing, so installing the hook
// links only this into an app that never posts a notification (decision 0006).

// MARK: - The host

public enum _UserNotificationsHost {
    /// The browser's current permission, when the host is in place.
    nonisolated(unsafe) public static var permission: (() -> UNAuthorizationStatus)?
    /// Asks the browser (a prompt the first time); the answer on the main actor.
    nonisolated(unsafe) public static var requestPermission: ((@escaping @MainActor (UNAuthorizationStatus) -> Void) -> Void)?
    /// Shows a notification; `onClick` is the user opening it.
    nonisolated(unsafe) public static var show: ((_ title: String, _ body: String, _ identifier: String, _ onClick: @escaping @MainActor () -> Void) -> Void)?
}

public enum UNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
    case ephemeral = 4
}
