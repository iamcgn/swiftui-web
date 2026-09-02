// Thin module: apps write `import SwiftUI` and get the SwiftUIWeb implementation.
// Foundation and Observation are re-exported because real SwiftUI does the same
// (CGFloat/CGRect, @Observable) and unmodified app sources depend on it.
@_exported import SwiftUIWebCore
@_exported import Foundation
@_exported import Observation
#if canImport(CoreGraphics)
// Apple platforms: CGRect.init(x:y:width:height:) etc. live in the CoreGraphics overlay, which
// `import Foundation` alone does not surface. Real SwiftUI re-exports CoreGraphics too.
@_exported import CoreGraphics
#endif

/// Marker used by the module-shadowing spike (Docs/decisions/0001-module-name.md).
public struct SwiftUIWebMarker: Sendable {
    public init() {}
    public static let implementation = "SwiftUIWeb"
}
