// Liquid Glass (iOS 26; Docs/coverage.md: `.glass` and `.glassProminent` button styles in 3
// apps, `glassEffect` in 2). The glass draws as a material in the shape: the regular material
// for `.regular`, the ultra-thin one for `.clear`, nothing for `.identity`, with the tint laid
// over it. The refraction and the morphing between glass shapes in a container are not drawn,
// so `GlassEffectContainer` lays out its content and `glassEffectID` keeps nothing. The glass
// button styles draw as the bordered and prominent ones.

/// The configuration of a Liquid Glass material.
public struct Glass: Equatable, Sendable {
    package enum Variant: Equatable, Sendable { case regular, clear, identity }
    package var variant: Variant
    package var tintColor: Color?
    package var isInteractive = false

    package init(variant: Variant) { self.variant = variant }

    /// The regular variant of glass.
    public static var regular: Glass { Glass(variant: .regular) }
    /// The clear variant of glass, more transparent than the regular one.
    public static var clear: Glass { Glass(variant: .clear) }
    /// Glass that draws nothing.
    public static var identity: Glass { Glass(variant: .identity) }

    /// The glass tinted with a colour.
    public func tint(_ color: Color?) -> Glass {
        var copy = self
        copy.tintColor = color
        return copy
    }

    /// The glass reacting to touches (it does not here).
    public func interactive(_ isEnabled: Bool = true) -> Glass {
        var copy = self
        copy.isInteractive = isEnabled
        return copy
    }
}

/// A transition of glass shapes between states in a container.
public struct GlassEffectTransition: Equatable, Sendable {
    package let value: Int
    public static var matchedGeometry: GlassEffectTransition { GlassEffectTransition(value: 0) }
    public static func matchedGeometry(properties: MatchedGeometryProperties = .frame, anchor: UnitPoint = .center) -> GlassEffectTransition { GlassEffectTransition(value: 0) }
    public static var materialize: GlassEffectTransition { GlassEffectTransition(value: 1) }
    public static var identity: GlassEffectTransition { GlassEffectTransition(value: 2) }
}

extension View {
    /// Applies the glass effect behind the view, in a capsule.
    nonisolated public func glassEffect(_ glass: Glass = .regular) -> some View {
        glassEffect(glass, in: Capsule())
    }

    /// Applies the glass effect behind the view, in the given shape.
    nonisolated public func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        background(_GlassBackground(glass: glass, shape: AnyShape(shape)))
    }

    /// Associates an identity with the view's glass, for morphing between states.
    nonisolated public func glassEffectID<ID: Hashable & Sendable>(_ id: ID?, in namespace: Namespace.ID) -> some View { self }

    /// Joins the view's glass with others of the same identity into one shape.
    nonisolated public func glassEffectUnion<ID: Hashable & Sendable>(id: ID?, namespace: Namespace.ID) -> some View { self }

    /// The transition of the view's glass as it is added or removed.
    nonisolated public func glassEffectTransition(_ transition: GlassEffectTransition) -> some View { self }
}

/// The glass behind a view: the material in the shape and the tint over it.
struct _GlassBackground: View {
    let glass: Glass
    let shape: AnyShape

    nonisolated init(glass: Glass, shape: AnyShape) {
        self.glass = glass
        self.shape = shape
    }

    var body: some View {
        if glass.variant == .identity {
            Color.clear
        } else {
            ZStack {
                shape.fill(Material(thickness: glass.variant == .clear ? .ultraThin : .regular))
                if let tint = glass.tintColor { shape.fill(tint.opacity(0.35)) }
            }
        }
    }
}

/// A container that combines the glass of the views in it (it lays them out as a stack would
/// not: the content is shown as it is).
public struct GlassEffectContainer<Content: View>: View {
    let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View { content }
}

/// A button style that draws the button on glass.
public struct GlassButtonStyle {
    package let glass: Glass
    @preconcurrency nonisolated public init() { glass = .regular }
    @preconcurrency nonisolated public init(_ glass: Glass) { self.glass = glass }
}

extension GlassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformButtonBody(configuration: configuration, kind: .bordered)
    }
}

/// A button style that draws the button on glass tinted with the accent colour.
public struct GlassProminentButtonStyle {
    @preconcurrency nonisolated public init() {}
}

extension GlassProminentButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformButtonBody(configuration: configuration, kind: .prominent)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    /// A button style that draws the button on glass.
    public static var glass: GlassButtonStyle { GlassButtonStyle() }
    /// A button style that draws the button on the given glass.
    public static func glass(_ glass: Glass) -> GlassButtonStyle { GlassButtonStyle(glass) }
}

extension ButtonStyle where Self == GlassProminentButtonStyle {
    /// A button style that draws the button on prominent glass.
    public static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}
