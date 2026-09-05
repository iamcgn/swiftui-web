/// A part of an app's user interface with a life cycle managed by the system.
@MainActor @preconcurrency
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }

    /// Hidden hook: the scene's root views, for hosts that mount them.
    @MainActor static func _windows(of scene: Self) -> [_WindowDescriptor]
}

extension Scene {
    public static func _windows(of scene: Self) -> [_WindowDescriptor] {
        Body._windows(of: scene.body)
    }

    @MainActor public static func _rootViews(of scene: Self) -> [AnyView] {
        _windows(of: scene).map { $0.make(nil) }
    }
}

/// `Never` as a scene reuses its `View` body; the default `_rootViews` is unreachable.
extension Never: Scene {}

/// A result builder for composing a collection of scenes into a single composite scene.
@resultBuilder
public enum SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> _TupleScene<(repeat each Content)> {
        _TupleScene(value: (repeat each content), roots: { value in
            var roots: [_WindowDescriptor] = []
            for scene in repeat each value { roots += _sceneWindows(scene) }
            return roots
        })
    }
    public static func buildExpression<Content: Scene>(_ content: Content) -> Content { content }
}

/// Two or more scenes in a `SceneBuilder` block.
public struct _TupleScene<T> {
    public var value: T
    package let roots: @MainActor (T) -> [_WindowDescriptor]
}

extension _TupleScene: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("_TupleScene has no body") }
    public static func _windows(of scene: _TupleScene<T>) -> [_WindowDescriptor] { scene.roots(scene.value) }
}

@MainActor
private func _sceneWindows<S: Scene>(_ scene: S) -> [_WindowDescriptor] { S._windows(of: scene) }

/// A scene that presents a group of identically structured windows.
/// A window scene the app declares: what to show, under which id, for which value type.
public struct _WindowDescriptor {
    public enum Kind: Equatable, Sendable { case windowGroup, window, settings, menuBarExtra }
    package var kind: Kind
    package var id: String?
    package var title: String?
    package var valueType: Any.Type?
    package var defaultSize: CGSize?
    /// Builds the root for a window; a window group over a value gets the box its binding writes to.
    package let make: @MainActor (_WindowValueBox?) -> AnyView

    package init(kind: Kind, id: String?, title: String?, valueType: Any.Type? = nil, make: @escaping @MainActor (_WindowValueBox?) -> AnyView) {
        self.kind = kind
        self.id = id
        self.title = title
        self.valueType = valueType
        self.make = make
    }
}

/// The value a window group window shows, shared with its content's binding.
@MainActor
public final class _WindowValueBox {
    public var value: Any?
    package var onChange: (() -> Void)?
    package init(_ value: Any?) { self.value = value }
}

public struct WindowGroup<Content: View> {
    package let descriptor: _WindowDescriptor

    public init(@ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: nil, title: nil) { _ in AnyView(view) }
    }

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: nil, title: title) { _ in AnyView(view) }
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: id, title: nil) { _ in AnyView(view) }
    }

    public init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: id, title: title) { _ in AnyView(view) }
    }

    /// A group whose windows show a value; `openWindow(value:)` opens one per distinct value.
    public init<D: Hashable & Codable>(for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: nil, title: nil, type: type, content: content)
    }

    public init<D: Hashable & Codable>(id: String, for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: id, title: nil, type: type, content: content)
    }

    public init<D: Hashable & Codable>(_ title: String, for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: nil, title: title, type: type, content: content)
    }

    public init<D: Hashable & Codable>(_ title: String, id: String, for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: id, title: title, type: type, content: content)
    }

    private static func valued<D: Hashable & Codable>(id: String?, title: String?, type: D.Type,
                                                       content: @escaping @MainActor (Binding<D?>) -> Content) -> _WindowDescriptor {
        _WindowDescriptor(kind: .windowGroup, id: id, title: title, valueType: type) { box in
            let box = box ?? _WindowValueBox(nil)
            let binding = Binding<D?>(get: { box.value as? D }, set: { box.value = $0; box.onChange?() })
            return AnyView(content(binding))
        }
    }
}

extension WindowGroup: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("WindowGroup has no body") }
    public static func _windows(of scene: WindowGroup<Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// A single window, opened by id.
public struct Window<Content: View> {
    package let descriptor: _WindowDescriptor

    public init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .window, id: id, title: title) { _ in AnyView(view) }
    }
}

extension Window: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("Window has no body") }
    public static func _windows(of scene: Window<Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// The settings window, opened by `openSettings`.
public struct Settings<Content: View> {
    package let descriptor: _WindowDescriptor

    public init(@ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .settings, id: "com.apple.SwiftUI.Settings", title: "Settings") { _ in AnyView(view) }
    }
}

extension Settings: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("Settings has no body") }
    public static func _windows(of scene: Settings<Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// A menu bar item; recorded but not shown (browsers have no menu bar).
public struct MenuBarExtra<Label: View, Content: View> {
    package let descriptor: _WindowDescriptor

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .menuBarExtra, id: nil, title: nil) { _ in AnyView(view) }
    }
}

extension MenuBarExtra where Label == Text {
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }

    public init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}

extension MenuBarExtra: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("MenuBarExtra has no body") }
    public static func _windows(of scene: MenuBarExtra<Label, Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// A scene with a modifier applied (default size; the others are accepted and ignored).
public struct _ModifiedScene<Base: Scene> {
    package let base: Base
    package let transform: (inout _WindowDescriptor) -> Void
}

extension _ModifiedScene: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("_ModifiedScene has no body") }
    public static func _windows(of scene: _ModifiedScene<Base>) -> [_WindowDescriptor] {
        Base._windows(of: scene.base).map { var d = $0; scene.transform(&d); return d }
    }
}

public enum WindowResizability: Sendable { case automatic, contentSize, contentMinSize }
public struct MenuBarExtraStyle: Sendable {
    public static var automatic: MenuBarExtraStyle { MenuBarExtraStyle() }
    public static var menu: MenuBarExtraStyle { MenuBarExtraStyle() }
    public static var window: MenuBarExtraStyle { MenuBarExtraStyle() }
}
public struct WindowStyle: Sendable {
    public static var automatic: WindowStyle { WindowStyle() }
    public static var hiddenTitleBar: WindowStyle { WindowStyle() }
    public static var titleBar: WindowStyle { WindowStyle() }
    public static var plain: WindowStyle { WindowStyle() }
}

extension Scene {
    /// The size a window opens at (its content is laid out in it).
    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        _ModifiedScene(base: self) { $0.defaultSize = CGSize(width: width, height: height) }
    }
    public func defaultSize(_ size: CGSize) -> some Scene { defaultSize(width: size.width, height: size.height) }
    public func windowResizability(_ resizability: WindowResizability) -> some Scene { _ModifiedScene(base: self) { _ in } }
    public func windowStyle(_ style: WindowStyle) -> some Scene { _ModifiedScene(base: self) { _ in } }
    public func menuBarExtraStyle(_ style: MenuBarExtraStyle) -> some Scene { _ModifiedScene(base: self) { _ in } }
    public func defaultPosition(_ position: UnitPoint) -> some Scene { _ModifiedScene(base: self) { _ in } }
}

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
    /// The app's window scenes, in declaration order.
    @MainActor
    public static func _windows() -> [_WindowDescriptor] {
        Body._windows(of: Self().body)
    }

    /// The root of the main window: the first window group (or window).
    @MainActor
    public static func _rootView() -> AnyView {
        let windows = _windows()
        let main = windows.first { $0.kind == .windowGroup || $0.kind == .window } ?? windows.first
        return main?.make(nil) ?? AnyView(EmptyView())
    }
}
