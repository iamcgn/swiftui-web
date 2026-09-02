/// A resolved colour in sRGB with straight alpha, components 0…1.
public struct RGBA: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 8-bit components, as in a PNG or a CSS `rgb()`.
    public init(r: Int, g: Int, b: Int, a: Double = 1) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a)
    }

    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 1, green: 1, blue: 1)

    public func multiplyingAlpha(by factor: Double) -> RGBA {
        var copy = self
        copy.alpha *= factor
        return copy
    }
}

/// Font description a painter needs (no environment left to resolve).
public struct DisplayFont: Hashable, Sendable {
    public var family: String
    public var size: CGFloat
    public var weight: Int
    public var italic: Bool

    public init(_ font: ResolvedFont) {
        family = font.family
        size = font.size
        weight = font.weight.value
        italic = font.italic
    }
}

/// One drawing command. Coordinates are absolute points in the window, already rounded to the
/// pixel grid where SwiftUI rounds (frame edges).
public enum DisplayCommand: Equatable, Sendable {
    case save
    case restore
    case clipRect(CGRect)
    case clipRRect(CGRect, cornerRadius: CGFloat)
    case clipPath(Path)
    case beginGroup(opacity: Double)
    case endGroup
    case fillRect(CGRect, RGBA)
    case fillRRect(CGRect, cornerRadius: CGFloat, RGBA)
    case fillPath(Path, RGBA)
    case strokePath(Path, lineWidth: CGFloat, RGBA)
    /// Draws one line of text with its baseline at `origin.y`.
    case drawText(String, DisplayFont, origin: CGPoint, RGBA)
}

/// The flat command list a painter consumes for one frame (decision 0002).
public struct DisplayList: Equatable, Sendable {
    public var commands: [DisplayCommand] = []

    public init() {}

    public mutating func append(_ command: DisplayCommand) {
        commands.append(command)
    }

    /// Runs `body` between `save` and `restore`.
    public mutating func withSavedState(_ body: (inout DisplayList) -> Void) {
        commands.append(.save)
        body(&self)
        commands.append(.restore)
    }

    public var isEmpty: Bool { commands.isEmpty }
}

extension DisplayCommand: CustomStringConvertible {
    public var description: String {
        func f(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }
        func r(_ rect: CGRect) -> String { "(\(f(rect.minX)), \(f(rect.minY)), \(f(rect.width)), \(f(rect.height)))" }
        func c(_ color: RGBA) -> String {
            let hex = String(Int((color.red * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
                + String(Int((color.green * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
                + String(Int((color.blue * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
            return color.alpha == 1 ? "#\(hex)" : "#\(hex)@\(color.alpha)"
        }
        switch self {
        case .save: return "save"
        case .restore: return "restore"
        case .clipRect(let rect): return "clipRect\(r(rect))"
        case .clipRRect(let rect, let radius): return "clipRRect\(r(rect)) r=\(f(radius))"
        case .clipPath(let path): return "clipPath(\(path.elements.count) elements)"
        case .beginGroup(let opacity): return "beginGroup(opacity: \(opacity))"
        case .endGroup: return "endGroup"
        case .fillRect(let rect, let color): return "fillRect\(r(rect)) \(c(color))"
        case .fillRRect(let rect, let radius, let color): return "fillRRect\(r(rect)) r=\(f(radius)) \(c(color))"
        case .fillPath(let path, let color): return "fillPath(\(path.elements.count) elements) \(c(color))"
        case .strokePath(let path, let width, let color): return "strokePath(\(path.elements.count) elements) w=\(f(width)) \(c(color))"
        case .drawText(let text, let font, let origin, let color):
            return "drawText(\"\(text)\" \(font.family) \(f(font.size)) w\(font.weight) at \(f(origin.x)),\(f(origin.y)) \(c(color)))"
        }
    }
}

extension String {
    fileprivate func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
