// Foundation's `NSValue` on wasm, where Foundation's is missing: a box for a geometry value or a
// range. UIKit's keyboard notifications carry their frames in it (`cgRectValue`), and
// swift-custom-dump names it with only Foundation imported, so it lives here, beside CGRect,
// where both `import UIKit` and `import Foundation` (through CoreGraphics) reach it.
#if os(WASI)
import WebFoundation

/// A box for a geometry value in a notification's user info (`cgRectValue` as UIKit's).
public final class NSValue: Hashable, @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private enum Stored: Equatable { case rect(CGRect), point(CGPoint), size(CGSize), range(NSRange), double(Double), other(AnyHashable) }
    private let stored: Stored
    public init(cgRect: CGRect) { stored = .rect(cgRect) }
    public init(cgPoint: CGPoint) { stored = .point(cgPoint) }
    public init(cgSize: CGSize) { stored = .size(cgSize) }
    public init(range: NSRange) { stored = .range(range) }
    /// A value another framework boxes (AVFoundation's `NSValue(time:)`), and that value.
    public init(_webValue value: AnyHashable) { stored = .other(value) }
    public var _webValue: AnyHashable? { if case .other(let value) = stored { return value }; return nil }
    public var cgRectValue: CGRect { if case .rect(let r) = stored { return r }; return .zero }
    public var cgPointValue: CGPoint { if case .point(let p) = stored { return p }; return .zero }
    public var cgSizeValue: CGSize { if case .size(let s) = stored { return s }; return .zero }
    public var rangeValue: NSRange { if case .range(let r) = stored { return r }; return NSRange(location: NSNotFound, length: 0) }
    public static func == (lhs: NSValue, rhs: NSValue) -> Bool { lhs.stored == rhs.stored }
    public func hash(into hasher: inout Hasher) {
        switch stored {
        case .rect(let r): hasher.combine(r.minX); hasher.combine(r.minY); hasher.combine(r.width); hasher.combine(r.height)
        case .point(let p): hasher.combine(p.x); hasher.combine(p.y)
        case .size(let s): hasher.combine(s.width); hasher.combine(s.height)
        case .range(let r): hasher.combine(r.location); hasher.combine(r.length)
        case .double(let d): hasher.combine(d)
        case .other(let value): hasher.combine(value)
        }
    }
    public var description: String { "\(stored)" }
    public var debugDescription: String { description }
}

#endif
