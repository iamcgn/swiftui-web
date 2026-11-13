// Where the app's background work meets what runs the app: whether the app is in the background
// (the page hidden), which the SwiftUI runtime and the UIKit scene report, and the actions
// SwiftUI's `backgroundTask(_:action:)` scene modifier declares, which BackgroundTasks' scheduler
// launches. A module of its own, depending on nothing, so the runtime links only this into an app
// that never schedules a task (decision 0006).

@MainActor
public enum _BackgroundTasksHost {
    /// Whether the app is in the background: its page is hidden (another tab, a minimised window).
    public private(set) static var inBackground = false
    /// Told when `inBackground` changes, with its new value.
    public static var observers: [@MainActor (_ inBackground: Bool) -> Void] = []

    /// Whether the app's own reports (the SwiftUI runtime's page visibility, the UIKit scene's
    /// notifications) set the state. Tests turn it off and set the state themselves, so the
    /// runtimes other tests drive leave it alone.
    public static var followsApp = true

    /// The app reports its state (the page hidden or shown).
    public static func appStateChanged(inBackground value: Bool) {
        guard followsApp else { return }
        setInBackground(value)
    }

    /// Sets the app's state; the observers hear a change.
    public static func setInBackground(_ value: Bool) {
        guard value != inBackground else { return }
        inBackground = value
        for observer in observers { observer(value) }
    }

    /// The actions of the app's `.backgroundTask(.appRefresh(identifier))` scene modifiers, by
    /// identifier: what an app refresh task with that identifier runs.
    public static var appRefreshActions: [String: @Sendable () async -> Void] = [:]

    /// Tests: forgets the state, the observers and the actions, and stops following the app's
    /// reports (tests set the state with `setInBackground`).
    public static func _reset() {
        followsApp = false
        inBackground = false
        observers.removeAll()
        appRefreshActions.removeAll()
    }
}
