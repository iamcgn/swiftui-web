// Image contexts (Docs/elements/UIKit/Drawing.md): `UIGraphicsImageRenderer` and the older
// `UIGraphicsBeginImageContext` family run drawing code with a recording context as the current
// one and hand back a `UIImage` holding the recorded commands, which `draw(at:)`, `draw(in:)`
// and `UIImageView` replay scaled into their rectangle. The image is a vector recording, not a
// bitmap: it stays sharp at any size and costs no pixels.

/// The commands an image context recorded, in the image's coordinates (its size in points).
public final class UIImageDrawing: @unchecked Sendable {
    public let commands: [DisplayCommand]
    public let size: CGSize
    public let scale: CGFloat

    init(commands: [DisplayCommand], size: CGSize, scale: CGFloat) {
        self.commands = commands
        self.size = size
        self.scale = scale
    }

    /// The recording scaled into `rect`.
    func commands(in rect: CGRect) -> [DisplayCommand] {
        guard !commands.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let transform = CGAffineTransform(a: rect.width / size.width, b: 0, c: 0, d: rect.height / size.height, tx: rect.minX, ty: rect.minY)
        return [.save, .concat(transform)] + commands + [.restore]
    }
}

/// The scale and opacity an image renderer draws with.
public final class UIGraphicsImageRendererFormat: @unchecked Sendable {
    public var scale: CGFloat
    public var opaque = false
    public var preferredRange = Range.standard
    public enum Range: Int, Sendable { case unspecified = -1, automatic = 0, standard = 1, extended = 2 }

    public init() { scale = 2 }

    /// The main screen's format.
    @MainActor public static func `default`() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return format
    }
    @MainActor public static func preferred() -> UIGraphicsImageRendererFormat { .default() }
}

/// What the renderer's drawing block receives: the recording context and shorthands.
@MainActor
public final class UIGraphicsImageRendererContext {
    public let cgContext: UIGraphicsRecordingContext
    public let format: UIGraphicsImageRendererFormat
    let bounds: CGRect

    init(cgContext: UIGraphicsRecordingContext, format: UIGraphicsImageRendererFormat, bounds: CGRect) {
        self.cgContext = cgContext
        self.format = format
        self.bounds = bounds
    }

    public func fill(_ rect: CGRect) { cgContext.fill(rect) }
    public func fill(_ rect: CGRect, blendMode: CGBlendMode) { cgContext.fill(rect) }
    public func stroke(_ rect: CGRect) { cgContext.stroke(rect) }
    public func stroke(_ rect: CGRect, blendMode: CGBlendMode) { cgContext.stroke(rect) }
    public func clip(to rect: CGRect) { cgContext.clip(to: rect) }
    /// What has been drawn so far, as an image.
    public var currentImage: UIImage { UIImage(drawing: UIImageDrawing(commands: cgContext.commands, size: bounds.size, scale: format.scale)) }
}

/// Runs drawing code and returns what it drew as an image.
@MainActor
public final class UIGraphicsImageRenderer {
    public let format: UIGraphicsImageRendererFormat
    public let bounds: CGRect
    public let allowsImageOutput = true

    public init(bounds: CGRect, format: UIGraphicsImageRendererFormat) {
        self.bounds = bounds
        self.format = format
    }
    public convenience init(bounds: CGRect) { self.init(bounds: bounds, format: .default()) }
    public convenience init(size: CGSize, format: UIGraphicsImageRendererFormat) { self.init(bounds: CGRect(origin: .zero, size: size), format: format) }
    public convenience init(size: CGSize) { self.init(bounds: CGRect(origin: .zero, size: size), format: .default()) }

    /// Runs `actions` with a fresh context (the image's origin at the bounds' origin) and
    /// returns the recording as an image the size of the bounds.
    public func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let recorder = UIGraphicsRecordingContext(origin: CGPoint(x: -bounds.minX, y: -bounds.minY), scale: format.scale)
        let context = UIGraphicsImageRendererContext(cgContext: recorder, format: format, bounds: bounds)
        UIGraphicsPushContext(recorder)
        actions(context)
        UIGraphicsPopContext()
        recorder.finish()
        return UIImage(drawing: UIImageDrawing(commands: recorder.commands, size: bounds.size, scale: format.scale))
    }
}

// MARK: - The older image context functions

@MainActor private var imageContexts: [(recorder: UIGraphicsRecordingContext, size: CGSize)] = []

/// Makes a recording context of `size` the current one until `UIGraphicsEndImageContext`.
@MainActor public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
    let recorder = UIGraphicsRecordingContext(origin: .zero, scale: scale == 0 ? UIScreen.main.scale : scale)
    imageContexts.append((recorder, size))
    UIGraphicsPushContext(recorder)
}
@MainActor public func UIGraphicsBeginImageContext(_ size: CGSize) { UIGraphicsBeginImageContextWithOptions(size, false, 1) }

/// What the current image context has recorded so far, or nil outside one.
@MainActor public func UIGraphicsGetImageFromCurrentImageContext() -> UIImage? {
    guard let current = imageContexts.last, UIGraphicsGetCurrentContext() === current.recorder else { return nil }
    return UIImage(drawing: UIImageDrawing(commands: current.recorder.commands, size: current.size, scale: current.recorder.scale))
}

@MainActor public func UIGraphicsEndImageContext() {
    guard let current = imageContexts.popLast() else { return }
    if UIGraphicsGetCurrentContext() === current.recorder { UIGraphicsPopContext() }
    current.recorder.finish()
}
