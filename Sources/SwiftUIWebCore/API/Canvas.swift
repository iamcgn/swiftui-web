/// A view type that supports immediate mode drawing (`Docs/elements/Canvas.md`).
///
/// The renderer draws into a `GraphicsContext` that records display-list commands in the
/// canvas's coordinate space: paths are filled and stroked with colours, text is laid out with
/// the environment's font, and the context's transform, opacity and clip apply to what follows.
public struct Canvas<Symbols: View>: View {
    package let renderer: _CanvasRenderer
    package let opaque: Bool
    package let colorMode: ColorRenderingMode
    package let rendersAsynchronously: Bool
    package let symbols: Symbols

    /// Creates and configures a canvas.
    public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void, @ViewBuilder symbols: () -> Symbols) {
        self.renderer = _CanvasRenderer(renderer)
        self.opaque = opaque
        self.colorMode = colorMode
        self.rendersAsynchronously = rendersAsynchronously
        self.symbols = symbols()
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Canvas<Symbols>>) -> TypedNode<Canvas<Symbols>> {
        CanvasNode(context)
    }
}

extension Canvas where Symbols == EmptyView {
    /// Creates and configures a canvas without symbols.
    public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
        self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer) { EmptyView() }
    }
}

/// The working color space and storage format used to render a canvas.
public enum ColorRenderingMode: Hashable, Sendable {
    case nonLinear, linear, extendedLinear
}

/// Holds a canvas renderer (a class so the runtime's field reflection ignores it).
package final class _CanvasRenderer {
    package let draw: (inout GraphicsContext, CGSize) -> Void
    package init(_ draw: @escaping (inout GraphicsContext, CGSize) -> Void) { self.draw = draw }
}

/// The records a `GraphicsContext` appends to (shared by copies of the context).
@MainActor
package final class _GraphicsRecorder {
    package var list = DisplayList()
    package let environment: EnvironmentValues
    package let textEngine: any TextEngine
    package let scale: CGFloat

    package init(environment: EnvironmentValues, textEngine: any TextEngine, scale: CGFloat) {
        self.environment = environment
        self.textEngine = textEngine
        self.scale = scale
    }
}

/// An immediate-mode drawing destination, and its current state.
public struct GraphicsContext {
    package let recorder: _GraphicsRecorder
    /// The current transform from the context's space to the canvas's.
    public var transform: CGAffineTransform = .identity
    /// The opacity of drawing that follows.
    public var opacity: Double = 1
    /// The blend mode of drawing that follows (only `.normal` is painted).
    public var blendMode: BlendMode = .normal
    /// Clips accumulated on this context, in the canvas's space.
    package var clips: [(Path, Bool)] = []
    /// The environment of the canvas view.
    @MainActor public var environment: EnvironmentValues { recorder.environment }

    package init(recorder: _GraphicsRecorder) { self.recorder = recorder }

    /// A color or pattern that you can use to outline or fill paths and shapes.
    public struct Shading: Sendable {
        package enum Kind: Sendable {
            case color(Color), foreground, background
            /// Gradients in the context's space (transformed when drawn).
            case linear(Gradient, start: CGPoint, end: CGPoint)
            case radial(Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
            case conic(Gradient, center: CGPoint, angle: Angle)
            /// A shape style resolved against the drawn path's bounds.
            case style(any ShapeStyle)
        }
        package let kind: Kind

        public static func color(_ color: Color) -> Shading { Shading(kind: .color(color)) }
        public static var foreground: Shading { Shading(kind: .foreground) }
        public static var backgroundStyle: Shading { Shading(kind: .background) }
        public static func color(red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
            Shading(kind: .color(Color(red: red, green: green, blue: blue, opacity: opacity)))
        }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(kind: .linear(gradient, start: startPoint, end: endPoint))
        }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(kind: .radial(gradient, center: center, startRadius: startRadius, endRadius: endRadius))
        }
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = .zero, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(kind: .conic(gradient, center: center, angle: angle))
        }
        public static func style<S: ShapeStyle>(_ style: S) -> Shading { Shading(kind: .style(style)) }

        /// The flat colour of a colour shading (gradients resolve through `gradient`).
        @MainActor package func resolve(in environment: EnvironmentValues) -> RGBA {
            switch kind {
            case .color(let color): return color.resolve(in: environment)
            case .foreground: return (environment.foregroundColor ?? .primary).resolve(in: environment)
            case .background: return Color.white.resolve(in: environment)
            case .style(let style): return (style as? Color ?? .primary).resolve(in: environment)
            case .linear, .radial, .conic: return Color.primary.resolve(in: environment)
            }
        }

        /// The gradient a gradient shading paints, in the canvas's absolute space: the
        /// context's points through `transform`, a style against the path's `bounds`.
        @MainActor package func gradient(bounds: CGRect, transform: CGAffineTransform, environment: EnvironmentValues) -> DisplayGradient? {
            let magnitude = (transform.a * transform.a + transform.b * transform.b).squareRoot()
            switch kind {
            case .linear(let gradient, let start, let end):
                return DisplayGradient(kind: .linear(start: start.applying(transform), end: end.applying(transform)), stops: gradient.resolvedStops(in: environment))
            case .radial(let gradient, let center, let r0, let r1):
                return DisplayGradient(kind: .radial(center: center.applying(transform), startRadius: r0 * magnitude, endRadius: r1 * magnitude),
                                       stops: gradient.resolvedStops(in: environment))
            case .conic(let gradient, let center, let angle):
                return DisplayGradient(kind: .angular(center: center.applying(transform), startAngle: angle.radians + _atan2(Double(transform.b), Double(transform.a))),
                                       stops: gradient.resolvedStops(in: environment))
            case .style(let style):
                return (style as? any _GradientStyle)?._resolveGradient(in: bounds, environment: environment)
            case .color, .foreground, .background:
                return nil
            }
        }
    }

    /// Options for gradient shadings (accepted; gradients neither mirror nor repeat here).
    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let `repeat` = GradientOptions(rawValue: 1)
        public static let mirror = GradientOptions(rawValue: 2)
        public static let linearColor = GradientOptions(rawValue: 4)
    }

    // MARK: Transforms

    public mutating func translateBy(x: CGFloat, y: CGFloat) { transform = transform.translatedBy(x: x, y: y) }
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { transform = transform.scaledBy(x: x, y: y) }
    public mutating func rotate(by angle: Angle) { transform = transform.rotated(by: CGFloat(angle.radians)) }
    public mutating func concatenate(_ matrix: CGAffineTransform) { transform = matrix.concatenating(transform) }

    // MARK: Clipping

    /// Adds a clip to the context, in the context's current space.
    public mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = ClipOptions()) {
        clips.append((path.applying(transform), style.isEOFilled))
    }

    /// Options that affect the use of clip shapes.
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let inverse = ClipOptions(rawValue: 1)
    }

    /// The bounding rectangle of the intersection of all current clip shapes.
    public var clipBoundingRect: CGRect {
        var result: CGRect? = nil
        for (path, _) in clips { result = result.map { $0.intersection(path.boundingRect) } ?? path.boundingRect }
        return result ?? CGRect(x: -CGFloat.infinity, y: -CGFloat.infinity, width: CGFloat.infinity, height: CGFloat.infinity)
    }

    // MARK: Drawing

    @MainActor private func withState(_ body: (inout DisplayList) -> Void) {
        let needsGroup = opacity < 1
        let needsClip = !clips.isEmpty
        if needsGroup { recorder.list.append(.beginGroup(opacity: opacity)) }
        if needsClip {
            recorder.list.append(.save)
            for (path, eo) in clips { recorder.list.append(.clipPath(path, eoFill: eo)) }
        }
        body(&recorder.list)
        if needsClip { recorder.list.append(.restore) }
        if needsGroup { recorder.list.append(.endGroup) }
    }

    /// Fills a path with the given shading.
    @MainActor public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        guard opacity > 0 else { return }
        let transformed = path.applying(transform)
        if let gradient = shading.gradient(bounds: transformed.boundingRect, transform: transform, environment: environment) {
            withState { $0.append(.fillGradient(transformed, gradient, eoFill: style.isEOFilled)) }
            return
        }
        let color = shading.resolve(in: environment)
        withState { $0.append(.fillPath(transformed, color, eoFill: style.isEOFilled)) }
    }

    /// Strokes a path with the given shading and line width.
    @MainActor public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    /// Strokes a path with the given shading and stroke style.
    @MainActor public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        guard opacity > 0 else { return }
        let color = shading.resolve(in: environment)
        let scale = (transform.a * transform.a + transform.b * transform.b).squareRoot()
        var scaled = style
        scaled.lineWidth = style.lineWidth * (scale > 0 ? scale : 1)
        let transformed = path.applying(transform)
        if let gradient = shading.gradient(bounds: transformed.boundingRect, transform: transform, environment: environment) {
            withState { $0.append(.strokeGradient(transformed, style: scaled, gradient)) }
            return
        }
        withState { $0.append(.strokePath(transformed, style: scaled, color)) }
    }

    /// Draws a text view, positioned by an anchor point.
    @MainActor public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        let resolved = resolve(text)
        let size = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        draw(resolved, in: CGRect(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y, width: size.width, height: size.height))
    }

    /// Draws a text view, wrapped and positioned at the top leading corner of a rectangle.
    @MainActor public func draw(_ text: Text, in rect: CGRect) {
        draw(resolve(text), in: rect)
    }

    @MainActor public func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
        let size = text.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        draw(text, in: CGRect(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y, width: size.width, height: size.height))
    }

    /// Draws resolved text into a rectangle (wrapped at its width, from its top leading corner).
    @MainActor public func draw(_ text: ResolvedText, in rect: CGRect) {
        guard opacity > 0 else { return }
        let layout = text.layout(width: rect.width.isFinite ? rect.width : nil)
        let isTranslation = transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1
        withState { list in
            if !isTranslation { list.append(.save); list.append(.concat(transform)) }
            let origin = isTranslation ? CGPoint(x: rect.minX + transform.tx, y: rect.minY + transform.ty) : rect.origin
            for line in layout.lines {
                for fragment in line.fragments where !fragment.text.isEmpty {
                    let run = min(max(fragment.run, 0), max(text.runs.count - 1, 0))
                    list.append(.drawText(fragment.text, DisplayFont(text.runs[run].font),
                                          origin: CGPoint(x: origin.x + fragment.x, y: origin.y + line.baseline), text.colors[run]))
                }
            }
            if !isTranslation { list.append(.restore) }
        }
    }

    /// Resolves a text view for measuring and repeated drawing.
    @MainActor public func resolve(_ text: Text) -> ResolvedText {
        let environment = recorder.environment
        let parts = text.parts()
        let runs = parts.map { part -> StyledRun in
            let font = part.modifiers.font ?? environment.font ?? environment.platformProfile.defaultFont
            var resolved = font.resolve(profile: environment.platformProfile)
            if let weight = part.modifiers.weight { resolved.weight = weight; resolved.weightOverridden = true }
            else if part.modifiers.bold { resolved.weight = environment.platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true }
            if part.modifiers.italic { resolved.italic = true }
            return StyledRun(part.string, font: resolved)
        }
        let inherited = environment.foregroundColor ?? .primary
        let colors = parts.map { ($0.modifiers.foregroundColor ?? inherited).resolve(in: environment) }
        return ResolvedText(runs: runs, colors: colors, engine: recorder.textEngine, options: environment.textLayoutOptions)
    }

    /// Draws a nested layer with a copy of the context (the layer's drawing goes through this
    /// context's opacity and clip).
    @MainActor public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        var layer = self
        try content(&layer)
    }

    /// Draws an image in a rectangle. Images need the asset catalog; a canvas cannot draw them yet.
    @MainActor public func draw(_ image: Image, in rect: CGRect) {}
    @MainActor public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {}
}

/// A text view resolved for drawing in a graphics context.
public struct ResolvedText {
    package let runs: [StyledRun]
    package let colors: [RGBA]
    package let engine: any TextEngine
    package let options: TextLayoutOptions

    @MainActor package func layout(width: CGFloat?) -> TextLayout {
        engine.layout(runs, options: options, width: width)
    }

    /// The size of the text when drawn in the given amount of space.
    @MainActor public func measure(in size: CGSize) -> CGSize {
        layout(width: size.width.isFinite ? size.width : nil).size
    }

    /// The first baseline of the text when drawn in the given amount of space.
    @MainActor public func firstBaseline(in size: CGSize) -> CGFloat {
        layout(width: size.width.isFinite ? size.width : nil).firstBaseline
    }
}

/// Modes for compositing a view with overlapping content (`View.blendMode`; a Canvas context's
/// `blendMode` is not painted yet).
public enum BlendMode: Hashable, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity, sourceAtop, destinationOver, destinationOut, plusDarker, plusLighter

    /// The mode's position in `allCases`, the display list's encoding.
    package var _index: Int { Self.allCases.firstIndex(of: self)! }
}
