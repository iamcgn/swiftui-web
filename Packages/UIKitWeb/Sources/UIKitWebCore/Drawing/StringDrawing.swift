// String, attributed string and image drawing inside `draw(_:)` (Docs/elements/UIKit/Drawing.md):
// `"text".draw(at:withAttributes:)`, `draw(in:withAttributes:)` and `size(withAttributes:)`,
// `NSAttributedString.draw(at:)` / `draw(in:)` / `size()`, `UIImage.draw(at:)` / `draw(in:)`,
// all recorded into the current graphics context through its transform, alpha and shadow.
// Measured on the iPhone SE simulator (uikit/draw/text).
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The paragraph attributes string drawing reads: the alignment and the line break mode.
open class NSParagraphStyle: @unchecked Sendable {
    public internal(set) var alignment: NSTextAlignment = .natural
    public internal(set) var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public internal(set) var lineSpacing: CGFloat = 0
    public init() {}
    public static var `default`: NSParagraphStyle { NSParagraphStyle() }
    public func mutableCopy() -> Any {
        let copy = NSMutableParagraphStyle()
        copy.alignment = alignment
        copy.lineBreakMode = lineBreakMode
        copy.lineSpacing = lineSpacing
        return copy
    }
}

open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {
    open override var alignment: NSTextAlignment { get { super.alignment } set { super.alignment = newValue } }
    open override var lineBreakMode: NSLineBreakMode { get { super.lineBreakMode } set { super.lineBreakMode = newValue } }
    open override var lineSpacing: CGFloat { get { super.lineSpacing } set { super.lineSpacing = newValue } }
}

#if os(WASI)
/// Foundation's attributed string is not in FoundationEssentials: a string with one attribute
/// dictionary (per-range attributes are not kept).
open class NSAttributedString: @unchecked Sendable {
    public struct Key: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    public let string: String
    let attributes: [Key: Any]
    public init(string: String, attributes: [Key: Any]? = nil) {
        self.string = string
        self.attributes = attributes ?? [:]
    }
    public init(string: String) {
        self.string = string
        attributes = [:]
    }
    public var length: Int { string.utf16.count }
    public func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [Key: Any] { attributes }
    /// The attributes of the whole string (this stand-in keeps one dictionary).
    var uniformAttributes: [Key: Any] { attributes }
}
public typealias NSRangePointer = UnsafeMutablePointer<NSRange>
public struct NSRange: Equatable, Sendable {
    public var location: Int
    public var length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
}
#else
extension NSAttributedString {
    /// The attributes at the string's start (drawing uses one font and colour for the string).
    var uniformAttributes: [Key: Any] { length > 0 ? attributes(at: 0, effectiveRange: nil) : [:] }
}
#endif

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
    public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
    public static let underlineStyle = NSAttributedString.Key("NSUnderline")
    public static let strikethroughStyle = NSAttributedString.Key("NSStrikethrough")
    public static let kern = NSAttributedString.Key("NSKern")
}

/// What string drawing resolves from an attribute dictionary: UIKit's defaults are Helvetica 12
/// (spelled as the 12 pt system font here) in black, natural alignment.
struct StringDrawingStyle {
    var font: UIFont = .systemFont(ofSize: 12)
    var color: UIColor = .black
    var alignment: NSTextAlignment = .natural
    var lineBreakMode: NSLineBreakMode = .byWordWrapping

    init(_ attributes: [NSAttributedString.Key: Any]?) {
        guard let attributes else { return }
        if let font = attributes[.font] as? UIFont { self.font = font }
        if let color = attributes[.foregroundColor] as? UIColor { self.color = color }
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
            alignment = paragraph.alignment
            lineBreakMode = paragraph.lineBreakMode
        }
    }
}

@MainActor
extension StringProtocol {
    /// Draws the string with its top-left corner at `point`, unwrapped (line breaks only at newlines).
    public func draw(at point: CGPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        UIGraphicsGetCurrentContext()?.drawString(String(self), style: StringDrawingStyle(attributes), at: point, width: nil, height: nil)
    }

    /// Draws the string wrapped in `rect`, the lines that fit its height only.
    public func draw(in rect: CGRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        UIGraphicsGetCurrentContext()?.drawString(String(self), style: StringDrawingStyle(attributes), at: rect.origin, width: rect.width, height: rect.height)
    }

    /// The string's unwrapped size in the attributes' font.
    public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> CGSize {
        UIGraphicsRecordingContext.measure(String(self), style: StringDrawingStyle(attributes), width: nil)
    }

    /// The string's bounding rectangle wrapped to `size.width` (the height ignored).
    public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], attributes: [NSAttributedString.Key: Any]? = nil, context: NSStringDrawingContext? = nil) -> CGRect {
        let width = size.width > 0 && size.width.isFinite ? size.width : nil
        return CGRect(origin: .zero, size: UIGraphicsRecordingContext.measure(String(self), style: StringDrawingStyle(attributes), width: width))
    }
}

public struct NSStringDrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 2)
    public static let usesDeviceMetrics = NSStringDrawingOptions(rawValue: 8)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 32)
}

public final class NSStringDrawingContext {
    public init() {}
}

@MainActor
extension NSAttributedString {
    public func draw(at point: CGPoint) {
        UIGraphicsGetCurrentContext()?.drawString(string, style: StringDrawingStyle(uniformAttributes), at: point, width: nil, height: nil)
    }
    public func draw(in rect: CGRect) {
        UIGraphicsGetCurrentContext()?.drawString(string, style: StringDrawingStyle(uniformAttributes), at: rect.origin, width: rect.width, height: rect.height)
    }
    public func size() -> CGSize {
        UIGraphicsRecordingContext.measure(string, style: StringDrawingStyle(uniformAttributes), width: nil)
    }
    public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], context: NSStringDrawingContext? = nil) -> CGRect {
        let width = size.width > 0 && size.width.isFinite ? size.width : nil
        return CGRect(origin: .zero, size: UIGraphicsRecordingContext.measure(string, style: StringDrawingStyle(uniformAttributes), width: width))
    }
}

@MainActor
extension UIImage {
    /// Draws the image at its own size with its top-left corner at `point`.
    public func draw(at point: CGPoint) { draw(in: CGRect(origin: point, size: size)) }
    public func draw(at point: CGPoint, blendMode: CGBlendMode, alpha: CGFloat) { draw(in: CGRect(origin: point, size: size), blendMode: blendMode, alpha: alpha) }
    /// Draws the image scaled into `rect`.
    public func draw(in rect: CGRect) { UIGraphicsGetCurrentContext()?.drawImage(self, in: rect, alpha: 1) }
    public func draw(in rect: CGRect, blendMode: CGBlendMode, alpha: CGFloat) { UIGraphicsGetCurrentContext()?.drawImage(self, in: rect, alpha: alpha) }
}

@MainActor
extension UIGraphicsRecordingContext {
    /// The string's laid-out size: the engine's width (unbounded, or wrapped to `width`) and
    /// the font's line pitch per line.
    static func measure(_ string: String, style: StringDrawingStyle, width: CGFloat?) -> CGSize {
        guard !string.isEmpty else { return .zero }
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(string, font: style.font.resolved)], options: TextLayoutOptions(), width: width)
        let lines = max(1, layout.lines.count)
        let pitch = style.font.lineHeight + style.font.leading
        return CGSize(width: layout.size.width, height: pitch * CGFloat(lines) - style.font.leading)
    }

    /// Lays the string out (unbounded, or wrapped to `width`) and records its lines from `origin`,
    /// aligned within `width`, dropping the lines past `height`.
    func drawString(_ string: String, style: StringDrawingStyle, at origin: CGPoint, width: CGFloat?, height: CGFloat?) {
        guard !string.isEmpty else { return }
        let font = style.font
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(string, font: font.resolved)], options: TextLayoutOptions(), width: width)
        let pitch = font.lineHeight + font.leading
        let color = style.color.rgba(for: UITraitCollection.current.userInterfaceStyle).multiplyingAlpha(by: Double(currentAlpha))
        let displayFont = DisplayFont(font.resolved)
        var commands: [DisplayCommand] = []
        for (index, line) in layout.lines.enumerated() {
            let top = pitch * CGFloat(index)
            if let height, top + font.lineHeight > height + 0.5 { break }
            let inset: CGFloat
            switch style.alignment {
            case .center: inset = width.map { ($0 - line.inkWidth) / 2 } ?? 0
            case .right: inset = width.map { $0 - line.inkWidth } ?? 0
            default: inset = 0
            }
            let baseline = origin.y + top + font.ascender
            for fragment in line.fragments {
                commands.append(.drawText(fragment.text, displayFont, origin: CGPoint(x: origin.x + inset + fragment.x, y: baseline), color))
            }
        }
        record(commands)
    }

    /// Records the image scaled into `rect`: a symbol through the symbol painter, a catalog
    /// image as an image draw, an image context's recording replayed.
    func drawImage(_ image: UIImage, in rect: CGRect, alpha: CGFloat) {
        let style = UITraitCollection.current.userInterfaceStyle
        let tint: RGBA? = image.renderingMode == .alwaysTemplate || (image.renderingMode == .automatic && image.isSystemSymbol)
            ? (image.tint ?? UIColor.label).rgba(for: style) : image.tint?.rgba(for: style)
        var list = DisplayList()
        if let drawing = image.drawing {
            for command in drawing.commands(in: rect) { list.append(command) }
        } else if image.isSystemSymbol {
            SymbolPainter.paint(name: image.name, in: rect, color: tint ?? UIColor.label.rgba(for: style), weight: image.symbolConfiguration?.weight?.css ?? 400, into: &list)
        } else {
            let catalog = UIKitScene.shared.assetCatalog
            guard let resource = catalog.image(named: image.name),
                  let variant = resource.variants.first(where: { $0.scale == scale }) ?? resource.variants.max(by: { $0.scale < $1.scale }) else { return }
            var draw = ImageDraw(file: variant.file, scale: variant.scale, pixelSize: CGSize(width: variant.pixelWidth, height: variant.pixelHeight), rect: rect)
            draw.tint = tint
            list.append(.drawImage(draw))
        }
        let opacity = Double(currentAlpha * alpha)
        if opacity < 1 {
            record([.beginGroup(opacity: opacity)] + list.commands + [.endGroup])
        } else {
            record(list.commands)
        }
    }
}
