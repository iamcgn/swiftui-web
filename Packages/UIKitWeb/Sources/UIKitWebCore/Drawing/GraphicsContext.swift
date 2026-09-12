// Custom drawing (Docs/elements/UIKit/Drawing.md): `draw(_:)` runs with a recording graphics
// context as the current context, which turns the CoreGraphics-style calls (`UIGraphicsGetCurrentContext`,
// `UIBezierPath.fill`, `UIColor.setFill`, `UIRectFill`) into display list commands in the view's
// coordinates. On wasm the context is what `CGContext` names; on Apple platforms CoreGraphics
// keeps that name and `UIGraphicsGetCurrentContext()` returns this class (decision 0014, Phase 3).

/// A graphics context recording into the display list: the current transform, colours, line
/// style and alpha form a state the `saveGState`/`restoreGState` stack keeps, paths are built in
/// user space and painted through the current transform.
@MainActor
public final class UIGraphicsRecordingContext {
    private struct State {
        var fill = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        var stroke = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        var lineWidth: CGFloat = 1
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var miterLimit: CGFloat = 10
        var dash: [CGFloat] = []
        var dashPhase: CGFloat = 0
        var alpha: CGFloat = 1
        var ctm = CGAffineTransform.identity
        var shadow: (color: RGBA, radius: CGFloat, offset: CGSize)?
    }

    /// The recorded commands (absolute coordinates through the origin the context was made for).
    private(set) var commands: [DisplayCommand] = []
    private var state = State()
    private var stack: [State] = []
    private var path = Path()
    /// Open groups (a shadow) per saved state, closed on restore.
    private var openGroups: [Int] = []
    private var groupsInState = 0
    let scale: CGFloat

    init(origin: CGPoint, scale: CGFloat) {
        self.scale = scale
        state.ctm = CGAffineTransform(translationX: origin.x, y: origin.y)
    }

    // MARK: State

    public func saveGState() {
        stack.append(state)
        openGroups.append(groupsInState)
        groupsInState = 0
    }

    public func restoreGState() {
        guard let saved = stack.popLast() else { return }
        for _ in 0..<groupsInState { commands.append(.endGroup) }
        groupsInState = openGroups.popLast() ?? 0
        // Clips made since the save end with it.
        if clipsInState > 0 { commands.append(.restore); clipsInState = 0 }
        clipsInState = clipStack.popLast() ?? 0
        state = saved
    }

    private var clipsInState = 0
    private var clipStack: [Int] = []

    public var ctm: CGAffineTransform { state.ctm }
    public func translateBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(translationX: x, y: y).concatenating(state.ctm) }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(scaleX: x, y: y).concatenating(state.ctm) }
    public func rotate(by angle: CGFloat) { state.ctm = CGAffineTransform(rotationAngle: angle).concatenating(state.ctm) }
    public func concatenate(_ transform: CGAffineTransform) { state.ctm = transform.concatenating(state.ctm) }

    public func setFillColor(_ color: CGColor) { if let rgba = RGBA(cgColor: color) { state.fill = rgba } }
    public func setStrokeColor(_ color: CGColor) { if let rgba = RGBA(cgColor: color) { state.stroke = rgba } }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.fill = RGBA(red: red, green: green, blue: blue, alpha: alpha) }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.stroke = RGBA(red: red, green: green, blue: blue, alpha: alpha) }
    public func setFillColor(gray: CGFloat, alpha: CGFloat) { state.fill = RGBA(red: gray, green: gray, blue: gray, alpha: alpha) }
    public func setStrokeColor(gray: CGFloat, alpha: CGFloat) { state.stroke = RGBA(red: gray, green: gray, blue: gray, alpha: alpha) }
    public func setLineWidth(_ width: CGFloat) { state.lineWidth = width }
    public func setLineCap(_ cap: CGLineCap) { state.lineCap = cap }
    public func setLineJoin(_ join: CGLineJoin) { state.lineJoin = join }
    public func setMiterLimit(_ limit: CGFloat) { state.miterLimit = limit }
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) { state.dash = lengths; state.dashPhase = phase }
    public func setAlpha(_ alpha: CGFloat) { state.alpha = alpha }
    public func setBlendMode(_ mode: CGBlendMode) {}
    public func setShouldAntialias(_ flag: Bool) {}
    public func setAllowsAntialiasing(_ flag: Bool) {}
    public func interpolationQuality(_ quality: Int) {}

    /// A shadow for what follows until the state is restored.
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) {
        guard let color, let rgba = RGBA(cgColor: color) else { state.shadow = nil; return }
        state.shadow = (rgba, blur, offset)
    }

    public func setShadow(offset: CGSize, blur: CGFloat) {
        state.shadow = (RGBA(red: 0, green: 0, blue: 0, alpha: 1.0 / 3), blur, offset)
    }

    // MARK: Paths

    public func beginPath() { path = Path() }
    public func move(to point: CGPoint) { path.move(to: point) }
    public func addLine(to point: CGPoint) { path.addLine(to: point) }
    public func addLines(between points: [CGPoint]) { path.addLines(points) }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { path.addCurve(to: end, control1: control1, control2: control2) }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) { path.addQuadCurve(to: end, control: control) }
    public func addRect(_ rect: CGRect) { path.addRect(rect) }
    public func addRects(_ rects: [CGRect]) { path.addRects(rects) }
    public func addEllipse(in rect: CGRect) { path.addEllipse(in: rect) }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        path.addArc(center: center, radius: radius, startAngle: Angle(radians: Double(startAngle)), endAngle: Angle(radians: Double(endAngle)), clockwise: !clockwise)
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) { path.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius) }
    public func addPath(_ other: Path) { path.addPath(other) }
    public func closePath() { path.closeSubpath() }
    public var isPathEmpty: Bool { path.isEmpty }
    public var currentPointOfPath: CGPoint { path.currentPoint ?? .zero }
    public var boundingBoxOfPath: CGRect { path.boundingRect }

    /// Fills the current path and clears it.
    public func fillPath() { fillPath(using: .winding) }
    public func fillPath(using rule: CGPathFillRule) {
        paintFill(path, evenOdd: rule == .evenOdd, alpha: 1)
        path = Path()
    }

    /// Strokes the current path and clears it.
    public func strokePath() {
        paintStroke(path, style: strokeStyle, alpha: 1)
        path = Path()
    }

    public func drawPath(using mode: CGPathDrawingMode) {
        switch mode {
        case .fill: paintFill(path, evenOdd: false, alpha: 1)
        case .eoFill: paintFill(path, evenOdd: true, alpha: 1)
        case .stroke: paintStroke(path, style: strokeStyle, alpha: 1)
        case .fillStroke: paintFill(path, evenOdd: false, alpha: 1); paintStroke(path, style: strokeStyle, alpha: 1)
        case .eoFillStroke: paintFill(path, evenOdd: true, alpha: 1); paintStroke(path, style: strokeStyle, alpha: 1)
        @unknown default: paintFill(path, evenOdd: false, alpha: 1)
        }
        path = Path()
    }

    public func fill(_ rect: CGRect) { paintFill(Path(rect), evenOdd: false, alpha: 1) }
    public func fill(_ rects: [CGRect]) { for rect in rects { fill(rect) } }
    public func stroke(_ rect: CGRect) { paintStroke(Path(rect), style: strokeStyle, alpha: 1) }
    public func stroke(_ rect: CGRect, width: CGFloat) {
        var style = strokeStyle
        style.lineWidth = width
        paintStroke(Path(rect), style: style, alpha: 1)
    }
    public func fillEllipse(in rect: CGRect) { paintFill(Path(ellipseIn: rect), evenOdd: false, alpha: 1) }
    public func strokeEllipse(in rect: CGRect) { paintStroke(Path(ellipseIn: rect), style: strokeStyle, alpha: 1) }
    public func strokeLineSegments(between points: [CGPoint]) {
        var segments = Path()
        var index = 0
        while index + 1 < points.count {
            segments.move(to: points[index])
            segments.addLine(to: points[index + 1])
            index += 2
        }
        paintStroke(segments, style: strokeStyle, alpha: 1)
    }
    /// Clears to transparent: the view's ground shows (drawn as nothing).
    public func clear(_ rect: CGRect) {}

    // MARK: Clipping

    /// Clips to the current path (and clears it) until the state is restored.
    public func clip() { clip(using: .winding) }
    public func clip(using rule: CGPathFillRule) {
        clip(to: path, evenOdd: rule == .evenOdd)
        path = Path()
    }
    public func clip(to rect: CGRect) { clip(to: Path(rect), evenOdd: false) }
    public func clip(to rects: [CGRect]) { clip(to: Path { for rect in rects { $0.addRect(rect) } }, evenOdd: false) }

    func clip(to path: Path, evenOdd: Bool) {
        commands.append(.save)
        commands.append(.clipPath(path.applying(state.ctm), eoFill: evenOdd))
        clipsInState += 1
    }

    // MARK: Transparency layers

    public func beginTransparencyLayer(auxiliaryInfo: [String: Any]?) {
        commands.append(.beginGroup(opacity: Double(state.alpha)))
        groupsInState += 1
    }
    public func endTransparencyLayer() {
        guard groupsInState > 0 else { return }
        commands.append(.endGroup)
        groupsInState -= 1
    }

    // MARK: Painting

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: state.lineWidth, lineCap: state.lineCap, lineJoin: state.lineJoin, miterLimit: state.miterLimit, dash: state.dash, dashPhase: state.dashPhase)
    }

    func fill(_ bezier: UIBezierPath, alpha: CGFloat) { paintFill(bezier.cgPath, evenOdd: bezier.usesEvenOddFillRule, alpha: alpha) }
    func stroke(_ bezier: UIBezierPath, alpha: CGFloat) { paintStroke(bezier.cgPath, style: bezier.strokeStyle, alpha: alpha) }

    private func withShadow(_ body: () -> Void) {
        if let shadow = state.shadow {
            commands.append(.beginShadow(shadow.color, radius: shadow.radius, offset: shadow.offset))
            body()
            commands.append(.endGroup)
        } else {
            body()
        }
    }

    private func paintFill(_ path: Path, evenOdd: Bool, alpha: CGFloat) {
        guard !path.isEmpty else { return }
        let color = state.fill.multiplyingAlpha(by: Double(state.alpha * alpha))
        withShadow { commands.append(.fillPath(path.applying(state.ctm), color, eoFill: evenOdd)) }
    }

    private func paintStroke(_ path: Path, style: StrokeStyle, alpha: CGFloat) {
        guard !path.isEmpty else { return }
        let color = state.stroke.multiplyingAlpha(by: Double(state.alpha * alpha))
        // The stroke width scales with the transform (uniformly, as far as it is uniform).
        let magnitude = (state.ctm.a * state.ctm.a + state.ctm.b * state.ctm.b).squareRoot()
        var scaled = style
        scaled.lineWidth = style.lineWidth * magnitude
        scaled.dash = style.dash.map { $0 * magnitude }
        scaled.dashPhase = style.dashPhase * magnitude
        withShadow { commands.append(.strokePath(path.applying(state.ctm), style: scaled, color)) }
    }

    /// The current alpha, for text and image drawing.
    var currentAlpha: CGFloat { state.alpha }

    /// Records commands spelled in the context's own coordinates: between a concat of the
    /// transform and a restore, inside the shadow group when there is one.
    func record(_ local: [DisplayCommand]) {
        guard !local.isEmpty else { return }
        let ctm = state.ctm
        withShadow {
            commands.append(.save)
            commands.append(.concat(ctm))
            commands.append(contentsOf: local)
            commands.append(.restore)
        }
    }

    /// Closes what is still open when drawing ends.
    func finish() {
        while !stack.isEmpty { restoreGState() }
        for _ in 0..<groupsInState { commands.append(.endGroup) }
        groupsInState = 0
        if clipsInState > 0 { commands.append(.restore); clipsInState = 0 }
    }
}

// MARK: - The current context

@MainActor private var contextStack: [UIGraphicsRecordingContext] = []

/// The current graphics context: the one a `draw(_:)` is running in, else nil.
@MainActor public func UIGraphicsGetCurrentContext() -> UIGraphicsRecordingContext? { contextStack.last }

@MainActor public func UIGraphicsPushContext(_ context: UIGraphicsRecordingContext) { contextStack.append(context) }
@MainActor public func UIGraphicsPopContext() { _ = contextStack.popLast() }

/// Fills `rect` with the current fill colour.
@MainActor public func UIRectFill(_ rect: CGRect) { UIGraphicsGetCurrentContext()?.fill(rect) }
/// Strokes a 1 pt frame inside `rect` with the current stroke colour.
@MainActor public func UIRectFrame(_ rect: CGRect) { UIGraphicsGetCurrentContext()?.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1) }
@MainActor public func UIRectClip(_ rect: CGRect) { UIGraphicsGetCurrentContext()?.clip(to: rect) }

@MainActor
extension UIColor {
    /// Sets this colour as the current context's fill colour.
    public func setFill() { UIGraphicsGetCurrentContext()?.setFillColor(rgba(for: UITraitCollection.current.userInterfaceStyle).cgColor) }
    /// Sets this colour as the current context's stroke colour.
    public func setStroke() { UIGraphicsGetCurrentContext()?.setStrokeColor(rgba(for: UITraitCollection.current.userInterfaceStyle).cgColor) }
    /// Sets this colour as both.
    public func set() { setFill(); setStroke() }
}

extension UIView {
    /// Runs `draw(_:)` with a recording context as the current one and appends what it drew:
    /// a view that does not override it draws nothing and costs one empty context.
    func drawCustomContent(into list: inout DisplayList, context: PaintContext) {
        let recorder = UIGraphicsRecordingContext(origin: context.origin, scale: context.scale)
        UIGraphicsPushContext(recorder)
        draw(bounds)
        UIGraphicsPopContext()
        recorder.finish()
        for command in recorder.commands { list.append(command) }
    }
}
