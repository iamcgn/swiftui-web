// String, attributed string and image drawing inside `draw(_:)` (Docs/elements/UIKit/Drawing.md):
// `"text".draw(at:withAttributes:)`, `draw(in:withAttributes:)` and `size(withAttributes:)`,
// `NSAttributedString.draw(at:)` / `draw(in:)` / `size()`, `UIImage.draw(at:)` / `draw(in:)`,
// all recorded into the current graphics context through its transform, alpha and shadow.
// Measured on the iPhone SE simulator (uikit/draw/text).
#if os(WASI)
import WebFoundation
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
/// Foundation's attributed string is not in FoundationEssentials: a string with attribute
/// dictionaries per range (UTF-16 offsets, as Foundation's).
open class NSAttributedString: @unchecked Sendable {
    public struct Key: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    public internal(set) var string: String
    /// The attribute runs covering the string in order (adjacent, non-overlapping).
    var runs: [(range: NSRange, attributes: [Key: Any])]

    public init(string: String, attributes: [Key: Any]? = nil) {
        self.string = string
        runs = string.isEmpty ? [] : [(NSRange(location: 0, length: string.utf16.count), attributes ?? [:])]
    }
    public init(string: String) {
        self.string = string
        runs = string.isEmpty ? [] : [(NSRange(location: 0, length: string.utf16.count), [:])]
    }
    public init(attributedString: NSAttributedString) {
        string = attributedString.string
        runs = attributedString.runs
    }
    public var length: Int { string.utf16.count }

    public func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [Key: Any] {
        guard let run = runs.first(where: { location >= $0.range.location && location < $0.range.location + $0.range.length }) else { return [:] }
        range?.pointee = run.range
        return run.attributes
    }

    public func attribute(_ key: Key, at location: Int, effectiveRange range: NSRangePointer?) -> Any? {
        attributes(at: location, effectiveRange: range)[key]
    }

    /// Calls `block` for each run in `range` (the stand-in's runs are already maximal).
    public func enumerateAttributes(in range: NSRange, options: EnumerationOptions = [], using block: ([Key: Any], NSRange, UnsafeMutablePointer<Bool>) -> Void) {
        var stop = false
        for run in runs where run.range.location < range.location + range.length && run.range.location + run.range.length > range.location {
            let start = max(run.range.location, range.location)
            let end = min(run.range.location + run.range.length, range.location + range.length)
            block(run.attributes, NSRange(location: start, length: end - start), &stop)
            if stop { break }
        }
    }

    public func enumerateAttribute(_ key: Key, in range: NSRange, options: EnumerationOptions = [], using block: (Any?, NSRange, UnsafeMutablePointer<Bool>) -> Void) {
        enumerateAttributes(in: range, options: options) { attributes, range, stop in block(attributes[key], range, stop) }
    }

    public struct EnumerationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let reverse = EnumerationOptions(rawValue: 1 << 1)
        public static let longestEffectiveRangeNotRequired = EnumerationOptions(rawValue: 1 << 20)
    }

    public func attributedSubstring(from range: NSRange) -> NSAttributedString {
        let utf16 = Array(string.utf16)
        let piece = String(decoding: utf16[max(0, range.location)..<min(utf16.count, range.location + range.length)], as: UTF16.self)
        let result = NSMutableAttributedString(string: "")
        result.string = piece
        result.runs = []
        enumerateAttributes(in: range) { attributes, sub, _ in
            result.runs.append((NSRange(location: sub.location - range.location, length: sub.length), attributes))
        }
        return result
    }

    /// The attributes at the string's start (string drawing uses one font and colour).
    var uniformAttributes: [Key: Any] { runs.first?.attributes ?? [:] }
}

/// An attributed string whose text and attributes can change.
open class NSMutableAttributedString: NSAttributedString, @unchecked Sendable {
    public func append(_ attributedString: NSAttributedString) {
        let offset = length
        string += attributedString.string
        runs += attributedString.runs.map { (NSRange(location: $0.range.location + offset, length: $0.range.length), $0.attributes) }
    }

    public func addAttribute(_ key: Key, value: Any, range: NSRange) { addAttributes([key: value], range: range) }

    public func addAttributes(_ attributes: [Key: Any], range: NSRange) {
        apply(range) { $0.merging(attributes) { _, new in new } }
    }

    public func setAttributes(_ attributes: [Key: Any]?, range: NSRange) {
        apply(range) { _ in attributes ?? [:] }
    }

    public func removeAttribute(_ key: Key, range: NSRange) {
        apply(range) { var copy = $0; copy[key] = nil; return copy }
    }

    public func replaceCharacters(in range: NSRange, with str: String) {
        let utf16 = Array(string.utf16)
        let head = String(decoding: utf16[0..<min(range.location, utf16.count)], as: UTF16.self)
        let tail = String(decoding: utf16[min(utf16.count, range.location + range.length)...], as: UTF16.self)
        let attributes = attributes(at: max(0, min(range.location, length - 1)), effectiveRange: nil)
        string = head + str + tail
        let delta = str.utf16.count - range.length
        var updated: [(range: NSRange, attributes: [Key: Any])] = []
        for run in runs {
            let start = run.range.location, end = start + run.range.length
            if end <= range.location { updated.append(run); continue }
            if start >= range.location + range.length { updated.append((NSRange(location: start + delta, length: run.range.length), run.attributes)); continue }
            // The run overlaps the replaced range: keep the parts outside it.
            if start < range.location { updated.append((NSRange(location: start, length: range.location - start), run.attributes)) }
            if end > range.location + range.length { updated.append((NSRange(location: range.location + str.utf16.count, length: end - (range.location + range.length)), run.attributes)) }
        }
        if !str.isEmpty { updated.append((NSRange(location: range.location, length: str.utf16.count), attributes)) }
        runs = updated.sorted { $0.range.location < $1.range.location }
    }

    /// Splits the runs at `range`'s ends and transforms the attributes inside it.
    private func apply(_ range: NSRange, _ transform: ([Key: Any]) -> [Key: Any]) {
        var updated: [(range: NSRange, attributes: [Key: Any])] = []
        let rangeEnd = range.location + range.length
        for run in runs {
            let start = run.range.location, end = start + run.range.length
            if end <= range.location || start >= rangeEnd { updated.append(run); continue }
            if start < range.location { updated.append((NSRange(location: start, length: range.location - start), run.attributes)) }
            let innerStart = max(start, range.location), innerEnd = min(end, rangeEnd)
            updated.append((NSRange(location: innerStart, length: innerEnd - innerStart), transform(run.attributes)))
            if end > rangeEnd { updated.append((NSRange(location: rangeEnd, length: end - rangeEnd), run.attributes)) }
        }
        runs = updated
    }
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
    public static let underlineColor = NSAttributedString.Key("NSUnderlineColor")
    public static let strikethroughColor = NSAttributedString.Key("NSStrikethroughColor")
    public static let kern = NSAttributedString.Key("NSKern")
    public static let link = NSAttributedString.Key("NSLink")
}

/// The underline and strikethrough styles (`NSUnderlineStyle.single.rawValue` as the
/// attribute's value); every non-zero style draws one line here. Foundation keeps the type in
/// UIKit and AppKit, so the module declares it everywhere.
public struct NSUnderlineStyle: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = NSUnderlineStyle(rawValue: 1)
    public static let thick = NSUnderlineStyle(rawValue: 2)
    public static let double = NSUnderlineStyle(rawValue: 9)
    public static let patternDot = NSUnderlineStyle(rawValue: 0x100)
    public static let patternDash = NSUnderlineStyle(rawValue: 0x200)
    public static let byWord = NSUnderlineStyle(rawValue: 0x8000)
}

/// What string drawing resolves from an attribute dictionary: UIKit's defaults are Helvetica 12
/// (spelled as the 12 pt system font here) in black, natural alignment. An attributed string
/// draws every range in its own font and colour, underlined or struck through where asked
/// (`.underlineStyle` / `.strikethroughStyle` other than 0, in `.underlineColor` /
/// `.strikethroughColor` or the text's colour); the paragraph style is read at the start.
struct StringDrawingStyle {
    struct Run {
        var text: String
        var font: UIFont
        var color: UIColor
        var underline: UIColor?
        var strikethrough: UIColor?
    }

    var font: UIFont = .systemFont(ofSize: 12)
    var color: UIColor = .black
    var alignment: NSTextAlignment = .natural
    var lineBreakMode: NSLineBreakMode = .byWordWrapping
    /// The ranges of an attributed string; empty for a plain string (one run in `font`).
    var runs: [Run] = []

    init(_ attributes: [NSAttributedString.Key: Any]?) {
        guard let attributes else { return }
        if let font = attributes[.font] as? UIFont { self.font = font }
        if let color = attributes[.foregroundColor] as? UIColor { self.color = color }
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
            alignment = paragraph.alignment
            lineBreakMode = paragraph.lineBreakMode
        }
    }

    @MainActor init(_ attributed: NSAttributedString) {
        self.init(attributed.uniformAttributes)
        let utf16 = Array(attributed.string.utf16)
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attributes, range, _ in
            let piece = String(decoding: utf16[range.location..<min(utf16.count, range.location + range.length)], as: UTF16.self)
            let color = attributes[.foregroundColor] as? UIColor ?? .black
            func line(_ style: NSAttributedString.Key, _ colorKey: NSAttributedString.Key) -> UIColor? {
                let value = attributes[style]
                let on = (value as? Int).map { $0 != 0 } ?? (value as? NSUnderlineStyle).map { !$0.isEmpty } ?? false
                return on ? (attributes[colorKey] as? UIColor ?? color) : nil
            }
            runs.append(Run(text: piece, font: attributes[.font] as? UIFont ?? .systemFont(ofSize: 12), color: color,
                            underline: line(.underlineStyle, .underlineColor), strikethrough: line(.strikethroughStyle, .strikethroughColor)))
        }
    }

    /// The runs to lay out: the attributed ranges, or the whole string in one.
    func styledRuns(for string: String) -> [Run] {
        runs.isEmpty ? [Run(text: string, font: font, color: color, underline: nil, strikethrough: nil)] : runs
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
        UIGraphicsGetCurrentContext()?.drawString(string, style: StringDrawingStyle(self), at: point, width: nil, height: nil)
    }
    public func draw(in rect: CGRect) {
        UIGraphicsGetCurrentContext()?.drawString(string, style: StringDrawingStyle(self), at: rect.origin, width: rect.width, height: rect.height)
    }
    public func size() -> CGSize {
        UIGraphicsRecordingContext.measure(string, style: StringDrawingStyle(self), width: nil)
    }
    public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], context: NSStringDrawingContext? = nil) -> CGRect {
        let width = size.width > 0 && size.width.isFinite ? size.width : nil
        return CGRect(origin: .zero, size: UIGraphicsRecordingContext.measure(string, style: StringDrawingStyle(self), width: width))
    }
}

@MainActor
extension UIImage {
    /// Draws the image at its own size with its top-left corner at `point`.
    public func draw(at point: CGPoint) { draw(in: CGRect(origin: point, size: size)) }
    public func draw(at point: CGPoint, blendMode: CGBlendMode, alpha: CGFloat) { draw(in: CGRect(origin: point, size: size), blendMode: blendMode, alpha: alpha) }
    /// Draws the image scaled into `rect`.
    public func draw(in rect: CGRect) { UIGraphicsGetCurrentContext()?.drawImage(self, in: rect, alpha: 1) }
    /// Draws the image scaled into `rect`, composited with `blendMode` at `alpha`.
    public func draw(in rect: CGRect, blendMode: CGBlendMode, alpha: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.withBlendMode(blendMode) { context.drawImage(self, in: rect, alpha: alpha) }
    }
}

@MainActor
extension UIGraphicsRecordingContext {
    /// The string's laid-out size: the engine's width (unbounded, or wrapped to `width`) and
    /// the tallest font's line pitch per line.
    static func measure(_ string: String, style: StringDrawingStyle, width: CGFloat?) -> CGSize {
        guard !string.isEmpty else { return .zero }
        let runs = style.styledRuns(for: string)
        let layout = UIKitScene.shared.textEngine.layout(runs.map { StyledRun($0.text, font: $0.font.resolved) }, options: TextLayoutOptions(), width: width)
        let lines = max(1, layout.lines.count)
        let font = runs.map(\.font).max { $0.lineHeight < $1.lineHeight } ?? style.font
        let pitch = font.lineHeight + font.leading
        return CGSize(width: layout.size.width, height: pitch * CGFloat(lines) - font.leading)
    }

    /// Lays the string out (unbounded, or wrapped to `width`) and records its lines from `origin`,
    /// aligned within `width`, dropping the lines past `height`; each fragment in its run's font
    /// and colour, with the run's underline and strikethrough (uikit/draw/rest).
    func drawString(_ string: String, style: StringDrawingStyle, at origin: CGPoint, width: CGFloat?, height: CGFloat?) {
        guard !string.isEmpty else { return }
        let runs = style.styledRuns(for: string)
        let font = runs.map(\.font).max { $0.lineHeight < $1.lineHeight } ?? style.font
        let layout = UIKitScene.shared.textEngine.layout(runs.map { StyledRun($0.text, font: $0.font.resolved) }, options: TextLayoutOptions(), width: width)
        let pitch = font.lineHeight + font.leading
        let appearance = UITraitCollection.current.userInterfaceStyle
        let colors = runs.map { $0.color.rgba(for: appearance).multiplyingAlpha(by: Double(currentAlpha)) }
        let fonts = runs.map { DisplayFont($0.font.resolved) }
        var commands: [DisplayCommand] = []
        var extent = CGRect(origin: origin, size: .zero)
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
                let run = min(max(0, fragment.run), runs.count - 1)
                let x = origin.x + inset + fragment.x
                commands.append(.drawText(fragment.text, fonts[run], origin: CGPoint(x: x, y: baseline), colors[run]))
                extent = extent.union(CGRect(x: x, y: baseline - runs[run].font.ascender, width: fragment.width, height: runs[run].font.lineHeight))
                let decorations = SystemFontMetricsTables.textDecorationMetrics(for: runs[run].font.resolved)
                if let underline = runs[run].underline {
                    // UIKit's string drawing draws the underline at least a point thick, its top
                    // a whole number of points under the baseline (the table's centre less half
                    // the thickness, rounded: 2 pt at 15 and 17 pt), antialiased, not snapped.
                    let thickness = max(1, decorations.thickness)
                    let top = baseline + (decorations.underlineOffset - thickness / 2).rounded()
                    commands.append(.fillRect(CGRect(x: x, y: top, width: fragment.width, height: thickness), underline.rgba(for: appearance).multiplyingAlpha(by: Double(currentAlpha))))
                }
                if let strikethrough = runs[run].strikethrough {
                    // The strikethrough centres on half the x-height above the baseline.
                    let top = baseline - decorations.xHeight / 2 - decorations.thickness / 2
                    commands.append(.fillRect(CGRect(x: x, y: top, width: fragment.width, height: decorations.thickness), strikethrough.rgba(for: appearance).multiplyingAlpha(by: Double(currentAlpha))))
                }
            }
        }
        record(commands, bounds: extent.insetBy(dx: -2, dy: -2))
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
            record([.beginGroup(opacity: opacity)] + list.commands + [.endGroup], bounds: rect)
        } else {
            record(list.commands, bounds: rect)
        }
    }
}
