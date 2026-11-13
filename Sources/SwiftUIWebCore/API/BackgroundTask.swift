// SwiftUI's background tasks: an app scene's `backgroundTask(.appRefresh(identifier))` declares
// what an app refresh task with the identifier runs. BackgroundTasks' scheduler launches it while
// the page is hidden (the app in the background), after the app submits a request with the
// identifier. A page has no background URL sessions, so the URL session tasks never run.
import BackgroundTasksHost

/// A kind of background work a scene's `backgroundTask(_:action:)` handles.
public struct BackgroundTask<Request, Response>: Sendable {
    enum Kind: Sendable {
        case appRefresh(String)
        case urlSession(String?)
        case urlSessionMatching(@Sendable (String) -> Bool)
    }
    let kind: Kind
}

extension BackgroundTask where Request == Void, Response == Void {
    /// The app refresh task with the identifier (a `BGAppRefreshTaskRequest`'s).
    public static func appRefresh(_ identifier: String) -> BackgroundTask<Void, Void> {
        BackgroundTask(kind: .appRefresh(identifier))
    }
    /// The background URL session with the identifier's events.
    public static func urlSession(_ identifier: String) -> BackgroundTask<Void, Void> {
        BackgroundTask(kind: .urlSession(identifier))
    }
}

extension BackgroundTask where Request == String, Response == Void {
    /// The events of every background URL session; the action gets the session's identifier.
    public static var urlSession: BackgroundTask<String, Void> { BackgroundTask(kind: .urlSession(nil)) }
    /// The events of the background URL sessions whose identifiers match.
    public static func urlSession(matching: @escaping @Sendable (String) -> Bool) -> BackgroundTask<String, Void> {
        BackgroundTask(kind: .urlSessionMatching(matching))
    }
}

extension Scene {
    /// Runs `action` when the system launches the app for the background task: for an app refresh
    /// task, when the app is in the background (its page hidden) and the request the app
    /// submitted with the identifier is due. The task ends when the action returns, and its
    /// expiration cancels the action's task.
    public func backgroundTask<Request: Sendable, Response: Sendable>(
        _ task: BackgroundTask<Request, Response>,
        action: @escaping @Sendable (Request) async -> Response
    ) -> some Scene {
        if case .appRefresh(let identifier) = task.kind, let request = () as? Request {
            _BackgroundTasksHost.appRefreshActions[identifier] = { _ = await action(request) }
        }
        return self
    }
}
