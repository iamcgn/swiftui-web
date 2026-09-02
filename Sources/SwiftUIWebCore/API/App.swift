/// A part of an app's user interface with a life cycle managed by the system.
@MainActor @preconcurrency
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }

    /// Hidden hook: the scene's root views, for hosts that mount them.
    @MainActor static func _rootViews(of scene: Self) -> [AnyView]
}

extension Scene {
    public static func _rootViews(of scene: Self) -> [AnyView] {
        Body._rootViews(of: scene.body)
    }
}

extension Never: Scene {
    public static func _rootViews(of scene: Never) -> [AnyView] { switch scene {} }
}

/// A result builder for composing a collection of scenes into a single composite scene.
@resultBuilder
public enum SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> _TupleScene<(repeat each Content)> {
        _TupleScene(value: (repeat each content), roots: { value in
            var roots: [AnyView] = []
            for scene in repeat each value { roots += _sceneRoots(scene) }
            return roots
        })
    }
    public static func buildExpression<Content: Scene>(_ content: Content) -> Content { content }
}

/// Two or more scenes in a `SceneBuilder` block.
public struct _TupleScene<T> {
    public var value: T
    package let roots: @MainActor (T) -> [AnyView]
}

extension _TupleScene: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("_TupleScene has no body") }
    public static func _rootViews(of scene: _TupleScene<T>) -> [AnyView] { scene.roots(scene.value) }
}

@MainActor
private func _sceneRoots<S: Scene>(_ scene: S) -> [AnyView] { S._rootViews(of: scene) }

/// A scene that presents a group of identically structured windows.
public struct WindowGroup<Content: View> {
    public var content: Content
    public var title: String?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

extension WindowGroup: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("WindowGroup has no body") }
    public static func _rootViews(of scene: WindowGroup<Content>) -> [AnyView] { [AnyView(scene.content)] }
}

/// A type that represents the structure and behavior of an app.
@MainActor @preconcurrency
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }

    init()

    /// Initializes and runs the app. The thin `SwiftUI` module provides the platform launcher.
    static func main()
}

/// Root view of the first window of an app, for hosts.
extension App {
    @MainActor
    public static func _rootView() -> AnyView {
        let app = Self()
        let roots = Body._rootViews(of: app.body)
        return roots.first ?? AnyView(EmptyView())
    }
}
