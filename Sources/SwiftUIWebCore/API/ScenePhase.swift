// Scene phase, URLs and user activities (Docs/elements/Lifecycle.md): the phase follows the
// page's visibility and focus through the host; `onOpenURL` handlers run for the URLs the host
// hands the runtime (`Runtime.openURL`); user activities are accepted and continued only when
// a host passes one (`Runtime.continueUserActivity`).
import WebFoundation

/// The operational state of a scene: visible and focused, visible without focus, or hidden.
public enum ScenePhase: Hashable, Comparable, Sendable {
    case background
    case inactive
    case active
}

package struct ScenePhaseKey: EnvironmentKey {
    package static let defaultValue = ScenePhase.active
}

extension EnvironmentValues {
    /// The scene's phase: `active` while the page is visible and focused, `inactive` while visible
    /// without focus, `background` while hidden.
    public var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
}

/// `onOpenURL`: registers a handler while the view is mounted.
public struct _OnOpenURLModifier {
    package let action: @MainActor (URL) -> Void
    package init(action: @escaping @MainActor (URL) -> Void) { self.action = action }
}

extension _OnOpenURLModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        OpenURLHandlerNode(context)
    }
}

/// `onContinueUserActivity`: registers a handler for an activity type while the view is mounted.
public struct _OnContinueUserActivityModifier {
    package let activityType: String
    package let action: @MainActor (NSUserActivity) -> Void
    package init(activityType: String, action: @escaping @MainActor (NSUserActivity) -> Void) {
        self.activityType = activityType
        self.action = action
    }
}

extension _OnContinueUserActivityModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ContinueActivityHandlerNode(context)
    }
}

extension View {
    /// Registers a handler to invoke when the view receives a URL for the scene or window the
    /// view is in (the host's URL changes, `Runtime.openURL`).
    nonisolated public func onOpenURL(perform action: @escaping @MainActor (URL) -> Void) -> some View {
        modifier(_OnOpenURLModifier(action: action))
    }

    /// Registers a handler to invoke in response to a user activity of the type (never from the
    /// web hosts; `Runtime.continueUserActivity` delivers one).
    nonisolated public func onContinueUserActivity(_ activityType: String, perform action: @escaping @MainActor (NSUserActivity) -> Void) -> some View {
        modifier(_OnContinueUserActivityModifier(activityType: activityType, action: action))
    }
}
