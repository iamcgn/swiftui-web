// `Color.Resolved` (iOS 17, macOS 14): a colour's concrete sRGB components in an environment, from
// `Color.resolve(in:)`. IceCubes' theme picks a contrasting tint by luminance of resolved colours,
// and Thunderbird's design system tells dynamic colours by resolving them in each appearance.
// Components are gamma-encoded sRGB, as Apple's; the linear ones apply the sRGB transfer.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

extension Color {
    /// A concrete colour: its sRGB components and opacity.
    public struct Resolved: Hashable, Sendable, ShapeStyle, CustomStringConvertible {
        public var red: Float
        public var green: Float
        public var blue: Float
        public var opacity: Float

        public init(red: Float, green: Float, blue: Float, opacity: Float = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.opacity = opacity
        }

        /// Components in `colorSpace`: linear sRGB is encoded; Display P3 is taken as sRGB, as
        /// `Color(_:red:green:blue:opacity:)` takes it.
        public init(colorSpace: RGBColorSpace = .sRGB, red: Float, green: Float, blue: Float, opacity: Float = 1) {
            if colorSpace == .sRGBLinear {
                self.init(red: Self.encoded(red), green: Self.encoded(green), blue: Self.encoded(blue), opacity: opacity)
            } else {
                self.init(red: red, green: green, blue: blue, opacity: opacity)
            }
        }

        public var linearRed: Float {
            get { Self.linear(red) }
            set { red = Self.encoded(newValue) }
        }
        public var linearGreen: Float {
            get { Self.linear(green) }
            set { green = Self.encoded(newValue) }
        }
        public var linearBlue: Float {
            get { Self.linear(blue) }
            set { blue = Self.encoded(newValue) }
        }

        /// The colour as a Core Graphics colour.
        public var cgColor: CGColor { _rgba.cgColor }

        /// `#RRGGBBAA`, as SwiftUI prints a resolved colour.
        public var description: String {
            let digits = Array("0123456789ABCDEF")
            var text = "#"
            for component in [red, green, blue, opacity] {
                let byte = Int((min(max(component, 0), 1) * 255).rounded())
                text.append(digits[byte >> 4])
                text.append(digits[byte & 15])
            }
            return text
        }

        package var _rgba: RGBA {
            RGBA(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(opacity))
        }

        package init(_ rgba: RGBA) {
            self.init(red: Float(rgba.red), green: Float(rgba.green), blue: Float(rgba.blue), opacity: Float(rgba.alpha))
        }

        /// The sRGB transfer function and its inverse; values outside 0…1 keep their sign, as
        /// extended sRGB does.
        static func linear(_ value: Float) -> Float {
            let magnitude = Double(abs(value))
            let result = magnitude <= 0.04045 ? magnitude / 12.92 : _pow((magnitude + 0.055) / 1.055, 2.4)
            return value < 0 ? -Float(result) : Float(result)
        }

        static func encoded(_ value: Float) -> Float {
            let magnitude = Double(abs(value))
            let result = magnitude <= 0.0031308 ? 12.92 * magnitude : 1.055 * _pow(magnitude, 1 / 2.4) - 0.055
            return value < 0 ? -Float(result) : Float(result)
        }
    }

    /// A colour of the resolved components.
    public init(_ resolved: Resolved) {
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue),
                  opacity: Double(resolved.opacity))
    }

    /// The colour's components in `environment`: its appearance, accent and asset catalog.
    /// Disfavoured, so code in this package that resolves to `RGBA` keeps doing so.
    @_disfavoredOverload
    public func resolve(in environment: EnvironmentValues) -> Resolved {
        Resolved(resolve(in: environment) as RGBA)
    }
}

/// Four sRGB components and the opacity, in an unkeyed container.
extension Color.Resolved: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.init(red: try container.decode(Float.self), green: try container.decode(Float.self),
                  blue: try container.decode(Float.self), opacity: try container.decode(Float.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(red)
        try container.encode(green)
        try container.encode(blue)
        try container.encode(opacity)
    }
}

extension Color {
    /// The colour `style` paints with in `environment`: the colour itself when it is one (or an
    /// erased one), otherwise the style resolved in the light and the dark appearance.
    package init<S: ShapeStyle>(_resolving style: S, in environment: EnvironmentValues) {
        if let color = style._asColor ?? (style as? AnyShapeStyle)?.base._asColor {
            self = color
            return
        }
        var light = environment, dark = environment
        light.colorScheme = .light
        dark.colorScheme = .dark
        self.init(storage: .dynamic(light: style.resolveColor(in: light), dark: style.resolveColor(in: dark)))
    }
}

extension ShapeStyle {
    /// The style as a colour when it is one: a `Color` or a resolved colour.
    package var _asColor: Color? {
        if let color = self as? Color { return color }
        if let resolved = self as? Color.Resolved { return Color(resolved) }
        if let blended = self as? any _BlendedStyle { return blended._blendBase._asColor }
        return nil
    }
}
