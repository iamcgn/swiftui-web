// Colour, blur and blend effects: modifiers that filter a view's rendering without changing
// its layout. Each wraps the content in a display-list group the painters composite after
// filtering (`DisplayFilter`) or with a blend mode.

/// Applies a colour matrix to the content's rendering.
@frozen
public struct _ColorMatrixEffect: Equatable {
    public enum Kind: Equatable {
        case brightness(Double), contrast(Double), saturation(Double), grayscale(Double), hueRotation(Angle)
        case colorInvert, colorMultiply(Color), luminanceToAlpha
    }
    public var kind: Kind
    public init(kind: Kind) { self.kind = kind }

    /// The matrix for the kind, colours resolved in `environment`.
    package func matrix(in environment: EnvironmentValues) -> ColorMatrix {
        switch kind {
        case .brightness(let amount): return .brightness(amount)
        case .contrast(let amount): return .contrast(amount)
        case .saturation(let amount): return .saturation(amount)
        case .grayscale(let amount): return .saturation(1 - amount)
        case .hueRotation(let angle): return .hueRotation(angle)
        case .colorInvert: return .invert
        case .colorMultiply(let color): return .multiply(color.resolve(in: environment))
        case .luminanceToAlpha: return .luminanceToAlpha
        }
    }
}

extension _ColorMatrixEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ColorMatrixNode(context)
    }
}

/// Blurs the content's rendering.
@frozen
public struct _BlurEffect: Equatable {
    public var radius: CGFloat
    public var isOpaque: Bool
    public init(radius: CGFloat, opaque: Bool) {
        self.radius = radius
        isOpaque = opaque
    }
}

extension _BlurEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        BlurNode(context)
    }
}

/// Composites the content with a blend mode.
@frozen
public struct _BlendModeEffect: Equatable {
    public var blendMode: BlendMode
    public init(blendMode: BlendMode) { self.blendMode = blendMode }
}

extension _BlendModeEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        BlendModeNode(context)
    }
}

extension View {
    /// Brightens this view by `amount`: it is added to every colour component (0 leaves the
    /// view as it is, 1 makes it white).
    nonisolated public func brightness(_ amount: Double) -> some View {
        modifier(_ColorMatrixEffect(kind: .brightness(amount)))
    }

    /// Scales the contrast of this view's colours about mid grey: 0 is grey, 1 unchanged.
    nonisolated public func contrast(_ amount: Double) -> some View {
        modifier(_ColorMatrixEffect(kind: .contrast(amount)))
    }

    /// Adjusts the colour saturation of this view: 0 is greyscale, 1 unchanged, more is vivid.
    nonisolated public func saturation(_ amount: Double) -> some View {
        modifier(_ColorMatrixEffect(kind: .saturation(amount)))
    }

    /// Reduces the colour intensity of this view: 0 unchanged, 1 fully grey.
    nonisolated public func grayscale(_ amount: Double) -> some View {
        modifier(_ColorMatrixEffect(kind: .grayscale(amount)))
    }

    /// Rotates the hues of this view's colours by `angle`.
    nonisolated public func hueRotation(_ angle: Angle) -> some View {
        modifier(_ColorMatrixEffect(kind: .hueRotation(angle)))
    }

    /// Inverts this view's colours.
    nonisolated public func colorInvert() -> some View {
        modifier(_ColorMatrixEffect(kind: .colorInvert))
    }

    /// Multiplies this view's colours (and alpha) by `color`'s.
    nonisolated public func colorMultiply(_ color: Color) -> some View {
        modifier(_ColorMatrixEffect(kind: .colorMultiply(color)))
    }

    /// Maps the luminance of this view to its alpha: black where the content is bright,
    /// transparent where it is dark.
    nonisolated public func luminanceToAlpha() -> some View {
        modifier(_ColorMatrixEffect(kind: .luminanceToAlpha))
    }

    /// Blurs this view with a Gaussian of sigma `radius`. An opaque blur keeps the view's
    /// edges and blurs only the colours within them.
    nonisolated public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
        modifier(_BlurEffect(radius: radius, opaque: opaque))
    }

    /// Composites this view over what is behind it with `blendMode`.
    nonisolated public func blendMode(_ blendMode: BlendMode) -> some View {
        modifier(_BlendModeEffect(blendMode: blendMode))
    }
}

/// Collects the content into one compositing group: the effects applied outside (opacity,
/// shadow, colour filters, blend modes) then act on the group's composite instead of on each
/// element.
@frozen
public struct _CompositingGroupEffect: Equatable {
    public init() {}
}

extension _CompositingGroupEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        CompositingGroupNode(context)
    }
}

/// Masks the content with another view's alpha.
public struct _MaskEffect<Mask: View> {
    public var mask: Mask
    public var alignment: Alignment

    public init(mask: Mask, alignment: Alignment) {
        self.mask = mask
        self.alignment = alignment
    }
}

extension _MaskEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        LayeredNode(context, layer: \.modifier.mask, alignment: \.modifier.alignment, mode: .mask)
    }
}

extension View {
    /// Wraps this view in a compositing group, so that effects applied to it (opacity, shadow,
    /// colour effects, blend modes) act on the whole rendering rather than on each element.
    nonisolated public func compositingGroup() -> some View {
        modifier(_CompositingGroupEffect())
    }

    /// Composites this view's contents into an offscreen image before applying effects; here
    /// the same as `compositingGroup` (`opaque` and `colorMode` are accepted without effect).
    nonisolated public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View {
        modifier(_CompositingGroupEffect())
    }

    /// Masks this view using the alpha channel of the given view, laid out over this view's
    /// frame with `alignment`.
    nonisolated public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
        modifier(_MaskEffect(mask: mask(), alignment: alignment))
    }

    /// Masks this view using the alpha channel of the given view.
    nonisolated public func mask<Mask: View>(_ mask: Mask) -> some View {
        modifier(_MaskEffect(mask: mask, alignment: .center))
    }
}
