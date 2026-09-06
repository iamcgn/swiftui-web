// `CGColor` as the display list sees it: on Apple platforms the CoreGraphics class in any
// colour space, on wasm the substrate's own (Geometry/CGTypes.swift).

extension RGBA {
    /// The colour's straight-alpha sRGB components, or nil when it cannot be read (an unusual
    /// colour space on Apple platforms).
    public init?(cgColor: CGColor) {
        #if canImport(CoreGraphics)
        let color: CGColor
        if let space = cgColor.colorSpace, space.model == .rgb {
            color = cgColor
        } else if let converted = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) {
            color = converted
        } else {
            return nil
        }
        guard let parts = color.components else { return nil }
        #else
        guard let parts = cgColor.components else { return nil }
        #endif
        switch parts.count {
        case 4: self.init(red: parts[0], green: parts[1], blue: parts[2], alpha: parts[3])
        case 3: self.init(red: parts[0], green: parts[1], blue: parts[2], alpha: 1)
        case 2: self.init(red: parts[0], green: parts[0], blue: parts[0], alpha: parts[1])
        case 1: self.init(red: parts[0], green: parts[0], blue: parts[0], alpha: 1)
        default: return nil
        }
    }

    /// The colour as a `CGColor` (sRGB).
    public var cgColor: CGColor {
        #if canImport(CoreGraphics)
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return CGColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }
}
