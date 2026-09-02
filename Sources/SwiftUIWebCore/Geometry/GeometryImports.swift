// One place that documents which module provides CGFloat & friends per platform; every file
// that needs them repeats the same three-line conditional import (Swift imports are per file).
#if canImport(CoreGraphics)
@_exported import CoreGraphics
#elseif !os(WASI)
@_exported import Foundation
#endif

extension CGSize {
    package static let unspecifiedIdeal = CGSize(width: 10, height: 10)

    @inline(__always) package func clamped(min lower: CGSize = .zero) -> CGSize {
        CGSize(width: Swift.max(width, lower.width), height: Swift.max(height, lower.height))
    }
}

extension CGFloat {
    @inline(__always) package func clamped(_ lower: CGFloat?, _ upper: CGFloat?) -> CGFloat {
        var value = self
        if let lower { value = Swift.max(value, lower) }
        if let upper { value = Swift.min(value, upper) }
        return value
    }
}
