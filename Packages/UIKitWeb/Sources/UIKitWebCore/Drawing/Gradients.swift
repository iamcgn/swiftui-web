// Gradients through the graphics context (Docs/elements/UIKit/Drawing.md): a `CGGradient` holds
// colour stops, `drawLinearGradient` and `drawRadialGradient` paint them over the current clip
// as gradient fills of the painted region. CoreGraphics blends the stops linearly in the
// gradient's colour space, which is what Canvas2D and the CoreGraphics painter do with the
// display list's stops, so there is no perceptual expansion here (unlike SwiftUI's gradients).
// The thin `UIKit` module names the class `CGGradient`: declared there, beside its re-export of
// CoreGraphics, the name shadows CoreGraphics's class (a real `CGGradient` cannot be read back)
// on Apple platforms and stands in for it on wasm, with `CGColorSpace`, `CFArray` and the
// drawing options here.
#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
#endif

#if !canImport(CoreGraphics)
/// A colour space stand-in on wasm: every colour is sRGB (decision 0006).
public final class CGColorSpace: @unchecked Sendable {
    public static let sRGB = "kCGColorSpaceSRGB"
    public static let genericGrayGamma2_2 = "kCGColorSpaceGenericGrayGamma2_2"
    /// Colour components before alpha: 3 for RGB, 1 for grey.
    public let numberOfComponents: Int
    init(numberOfComponents: Int) { self.numberOfComponents = numberOfComponents }
    public convenience init?(name: String) { self.init(numberOfComponents: name.contains("Gray") ? 1 : 3) }
}
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace(numberOfComponents: 3) }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace(numberOfComponents: 1) }

/// `[colors] as CFArray` in gradient code: an array of anything on wasm.
public typealias CFArray = [Any]

/// Whether a gradient extends past its start and end locations.
public struct CGGradientDrawingOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let drawsBeforeStartLocation = CGGradientDrawingOptions(rawValue: 1 << 0)
    public static let drawsAfterEndLocation = CGGradientDrawingOptions(rawValue: 1 << 1)
}
#endif

/// Colour stops for `drawLinearGradient` and `drawRadialGradient` (`CGGradient` to apps).
public final class UIGraphicsGradient: @unchecked Sendable {
    let stops: [DisplayGradient.Stop]

    init(stops: [DisplayGradient.Stop]) { self.stops = stops }

    /// Colours (a `CFArray` of `CGColor`s) at `locations` in 0…1, or evenly spaced without them.
    /// CoreGraphics takes the locations as a pointer; an array is what Swift code passes, and a
    /// pointer overload would make `locations: nil` ambiguous.
    public convenience init?(colorsSpace space: CGColorSpace?, colors: CFArray, locations: [CGFloat]?) {
        let rgbas = Self.colors(in: colors).compactMap { RGBA(cgColor: $0) }
        guard !rgbas.isEmpty else { return nil }
        self.init(stops: Self.stops(rgbas, locations: locations))
    }

    /// `count` colours as flat components (the space's components plus alpha each).
    public convenience init?(colorSpace space: CGColorSpace?, colorComponents: UnsafePointer<CGFloat>, locations: UnsafePointer<CGFloat>?, count: Int) {
        guard count > 0 else { return nil }
        let stride = (space?.numberOfComponents ?? 3) + 1
        let components = Array(UnsafeBufferPointer(start: colorComponents, count: count * stride))
        let rgbas: [RGBA] = (0..<count).map { index in
            let base = index * stride
            if stride == 2 { return RGBA(red: components[base], green: components[base], blue: components[base], alpha: components[base + 1]) }
            return RGBA(red: components[base], green: components[base + 1], blue: components[base + 2], alpha: components[base + stride - 1])
        }
        self.init(stops: Self.stops(rgbas, locations: locations.map { Array(UnsafeBufferPointer(start: $0, count: count)) }))
    }

    private static func stops(_ colors: [RGBA], locations: [CGFloat]?) -> [DisplayGradient.Stop] {
        let count = colors.count
        return colors.enumerated().map { index, color in
            let location: CGFloat
            if let locations, index < locations.count {
                location = min(max(locations[index], 0), 1)
            } else {
                location = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
            }
            return DisplayGradient.Stop(location: Double(location), color: color)
        }
    }

    private static func colors(in array: CFArray) -> [CGColor] {
        #if canImport(CoreGraphics)
        return (array as NSArray).compactMap { element in
            CFGetTypeID(element as CFTypeRef) == CGColor.typeID ? (element as! CGColor) : nil
        }
        #else
        return array.compactMap { $0 as? CGColor }
        #endif
    }
}

@MainActor
extension UIGraphicsRecordingContext {
    /// Paints the gradient along the line from `start` to `end` over the current clip: the band
    /// between the perpendiculars through the two points, extended past either by the options.
    public func drawLinearGradient(_ gradient: UIGraphicsGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, !gradient.stops.isEmpty else { return }
        let ux = dx / length, uy = dy / length
        let px = -uy, py = ux
        let reach: CGFloat = 1e5
        let from = options.contains(.drawsBeforeStartLocation) ? -reach : 0
        let to = options.contains(.drawsAfterEndLocation) ? length + reach : length
        func corner(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: start.x + ux * along + px * across, y: start.y + uy * along + py * across)
        }
        var band = Path()
        band.move(to: corner(from, -reach))
        band.addLine(to: corner(to, -reach))
        band.addLine(to: corner(to, reach))
        band.addLine(to: corner(from, reach))
        band.closeSubpath()
        let kind = DisplayGradient.Kind.linear(start: start.applying(ctm), end: end.applying(ctm))
        paintGradient(gradient, kind: kind, region: band, evenOdd: false)
    }

    /// Paints the gradient between the two circles over the current clip: inside the end
    /// circle and outside the start circle unless the options extend it.
    public func drawRadialGradient(_ gradient: UIGraphicsGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions) {
        guard !gradient.stops.isEmpty else { return }
        func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
            CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
        var region = Path()
        if options.contains(.drawsAfterEndLocation) {
            let reach: CGFloat = 1e5
            region.addRect(CGRect(x: endCenter.x - reach, y: endCenter.y - reach, width: reach * 2, height: reach * 2))
        } else {
            region.addEllipse(in: circle(endCenter, endRadius))
        }
        var evenOdd = false
        if !options.contains(.drawsBeforeStartLocation), startRadius > 0 {
            region.addEllipse(in: circle(startCenter, startRadius))
            evenOdd = true
        }
        let magnitude = (ctm.a * ctm.a + ctm.b * ctm.b).squareRoot()
        let kind: DisplayGradient.Kind
        if startCenter == endCenter {
            kind = .radial(center: endCenter.applying(ctm), startRadius: startRadius * magnitude, endRadius: endRadius * magnitude)
        } else {
            kind = .focalRadial(startCenter: startCenter.applying(ctm), startRadius: startRadius * magnitude, endCenter: endCenter.applying(ctm), endRadius: endRadius * magnitude)
        }
        paintGradient(gradient, kind: kind, region: region, evenOdd: evenOdd)
    }

    /// Records a gradient fill of `region` (user space) with the context's alpha and shadow.
    private func paintGradient(_ gradient: UIGraphicsGradient, kind: DisplayGradient.Kind, region: Path, evenOdd: Bool) {
        let alpha = Double(currentAlpha)
        let stops = alpha < 1 ? gradient.stops.map { DisplayGradient.Stop(location: $0.location, color: $0.color.multiplyingAlpha(by: alpha)) } : gradient.stops
        recordShadowed(.fillGradient(region.applying(ctm), DisplayGradient(kind: kind, stops: stops), eoFill: evenOdd))
    }
}
