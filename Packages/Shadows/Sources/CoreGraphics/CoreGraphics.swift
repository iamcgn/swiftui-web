// Apple's `CoreGraphics` module for wasm (Docs/coverage.md: 7 apps import it, mostly for
// `CGFloat` and the geometry types in a model file that imports nothing else): WebGraphics's
// geometry types under the module name, and the C library's maths, which CoreGraphics brings
// with it on iOS. Each name is imported on its own, so WebGraphics's other declarations stay
// out of the app's scope. The image types (`CGImage`, `CGColorSpace`, `CGDataProvider` and the
// bitmap layout names) are WebGraphics's too (Images/CGImage.swift); drawing (`CGContext`,
// `CGPath`) comes with UIKit and SwiftUI as before.
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
@_exported import class WebGraphics.CGImage
@_exported import class WebGraphics.CGColorSpace
@_exported import class WebGraphics.CGDataProvider
@_exported import enum WebGraphics.CGColorSpaceModel
@_exported import enum WebGraphics.CGImageAlphaInfo
@_exported import enum WebGraphics.CGImageByteOrderInfo
@_exported import struct WebGraphics.CGBitmapInfo
@_exported import enum WebGraphics.CGColorRenderingIntent
@_exported import enum WebGraphics.CGInterpolationQuality
@_exported import func WebGraphics.CGColorSpaceCreateDeviceRGB
@_exported import func WebGraphics.CGColorSpaceCreateDeviceGray
#endif
