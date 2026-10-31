// Apple's `CoreGraphics` module for wasm (Docs/coverage.md: 7 apps import it, mostly for
// `CGFloat` and the geometry types in a model file that imports nothing else): WebGraphics's
// geometry types under the module name, and the C library's maths, which CoreGraphics brings
// with it on iOS. Each name is imported on its own, so WebGraphics's other declarations stay
// out of the app's scope. Drawing (`CGContext`, `CGPath`, `CGImage`) comes with UIKit and
// SwiftUI as before.
#if os(WASI)
@_exported import WASILibc
@_exported import typealias WebGraphics.CGFloat
@_exported import struct WebGraphics.CGPoint
@_exported import struct WebGraphics.CGSize
@_exported import struct WebGraphics.CGRect
@_exported import struct WebGraphics.CGVector
@_exported import struct WebGraphics.CGAffineTransform
@_exported import class WebGraphics.CGColor
@_exported import enum WebGraphics.CGLineCap
@_exported import enum WebGraphics.CGLineJoin
#endif
