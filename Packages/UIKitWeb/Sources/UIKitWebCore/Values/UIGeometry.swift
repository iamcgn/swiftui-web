// Geometry values UIKit adds to CoreGraphics's.

/// Inset distances for views: top, left, bottom, right.
public struct UIEdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }

    public init() { self.init(top: 0, left: 0, bottom: 0, right: 0) }

    public static let zero = UIEdgeInsets()
}

extension CGRect {
    /// The rectangle shrunk by the insets.
    public func inset(by insets: UIEdgeInsets) -> CGRect {
        CGRect(x: minX + insets.left, y: minY + insets.top, width: width - insets.left - insets.right, height: height - insets.top - insets.bottom)
    }
}

/// Edge insets that follow the layout direction: top, leading, bottom, trailing.
public struct NSDirectionalEdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }

    public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }

    public static let zero = NSDirectionalEdgeInsets()
}

/// A position offset.
public struct UIOffset: Equatable, Hashable, Sendable {
    public var horizontal: CGFloat
    public var vertical: CGFloat
    public init(horizontal: CGFloat, vertical: CGFloat) { self.horizontal = horizontal; self.vertical = vertical }
    public init() { self.init(horizontal: 0, vertical: 0) }
    public static let zero = UIOffset()
}

/// The corners of a rectangle.
public struct UIRectCorner: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let topLeft = UIRectCorner(rawValue: 1)
    public static let topRight = UIRectCorner(rawValue: 2)
    public static let bottomLeft = UIRectCorner(rawValue: 4)
    public static let bottomRight = UIRectCorner(rawValue: 8)
    public static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

/// The edges of a rectangle.
public struct UIRectEdge: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let top = UIRectEdge(rawValue: 1)
    public static let left = UIRectEdge(rawValue: 2)
    public static let bottom = UIRectEdge(rawValue: 4)
    public static let right = UIRectEdge(rawValue: 8)
    public static let all: UIRectEdge = [.top, .left, .bottom, .right]
}

/// An axis in a view's coordinate space.
public struct UIAxis: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let horizontal = UIAxis(rawValue: 1)
    public static let vertical = UIAxis(rawValue: 2)
    public static let both: UIAxis = [.horizontal, .vertical]
}

/// The priority of a layout constraint or a content size preference.
public struct UILayoutPriority: Hashable, Sendable, RawRepresentable, Comparable {
    public let rawValue: Float
    public init(rawValue: Float) { self.rawValue = rawValue }
    public init(_ rawValue: Float) { self.rawValue = rawValue }
    public static let required = UILayoutPriority(1000)
    public static let defaultHigh = UILayoutPriority(750)
    public static let dragThatCanResizeScene = UILayoutPriority(510)
    public static let sceneSizeStayPut = UILayoutPriority(500)
    public static let dragThatCannotResizeScene = UILayoutPriority(490)
    public static let defaultLow = UILayoutPriority(250)
    public static let fittingSizeLevel = UILayoutPriority(50)
    public static func < (lhs: UILayoutPriority, rhs: UILayoutPriority) -> Bool { lhs.rawValue < rhs.rawValue }
    public static func + (lhs: UILayoutPriority, rhs: Float) -> UILayoutPriority { UILayoutPriority(lhs.rawValue + rhs) }
    public static func - (lhs: UILayoutPriority, rhs: Float) -> UILayoutPriority { UILayoutPriority(lhs.rawValue - rhs) }
}

/// Text alignment (`NSTextAlignment` on Apple platforms).
public enum NSTextAlignment: Int, Sendable {
    case left = 0, center = 1, right = 2, justified = 3, natural = 4
}

/// How text is broken or truncated.
public enum NSLineBreakMode: Int, Sendable {
    case byWordWrapping = 0, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle
}

/// The layout size fitting values `systemLayoutSizeFitting` accepts.
public enum UILayoutFittingSize {
    public static let compressed = CGSize.zero
    public static let expanded = CGSize(width: 10000, height: 10000)
}

extension UIView {
    public static let layoutFittingCompressedSize = UILayoutFittingSize.compressed
    public static let layoutFittingExpandedSize = UILayoutFittingSize.expanded
    /// The intrinsic content size a view reports along an axis it has no opinion about.
    public static let noIntrinsicMetric: CGFloat = -1
}
