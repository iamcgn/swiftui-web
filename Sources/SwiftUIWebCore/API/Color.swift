#if !os(WASI)
#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif
#endif

/// A representation of a color that adapts to a given context.
///
/// Step 5 provides the value type and its role as a flexible view (ideal size 10×10, fills its
/// proposal); the system colour table and painting arrive in step 7.
public struct Color: Hashable, Sendable {
    /// Resolved RGBA components in sRGB, 0…1.
    package enum Storage: Hashable, Sendable {
        case rgba(red: Double, green: Double, blue: Double, opacity: Double)
        case system(SystemColor)
        /// A colour set of the app's asset catalogs (decision 0011).
        case named(String)
    }

    package enum SystemColor: String, Hashable, Sendable, CaseIterable {
        case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown
        case white, gray, black, clear, primary, secondary, accentColor
        /// The colour of links (`Link`): the fixed blue macOS uses, not the accent.
        case link
        /// The ink controls are drawn with, at an alpha: black in the light appearance, white in
        /// the dark one (button fills, tracks, separators; Docs/elements/DarkMode.md).
        case controlInk
        /// The window's background (`windowBackgroundColor`).
        case windowBackground
        /// The background of text fields, lists and tables (`controlBackgroundColor`).
        case controlBackground
        /// Switch and slider knobs.
        case knob
    }

    package let storage: Storage
    package let opacityMultiplier: Double

    package init(storage: Storage, opacityMultiplier: Double = 1) {
        self.storage = storage
        self.opacityMultiplier = opacityMultiplier
    }

    /// Creates a constant color from red, green, and blue component values.
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.init(storage: .rgba(red: red, green: green, blue: blue, opacity: opacity))
    }

    #if os(WASI)
    /// Creates a color from a color set in the app's asset catalogs. There is no `Bundle` on wasm.
    public init(_ name: String) {
        self.init(storage: .named(name))
    }
    #else
    /// Creates a color from a color set in the app's asset catalogs; the bundle is ignored.
    public init(_ name: String, bundle: Bundle? = nil) {
        self.init(storage: .named(name))
    }
    #endif

    /// Creates a constant grayscale color.
    public init(white: Double, opacity: Double = 1) {
        self.init(storage: .rgba(red: white, green: white, blue: white, opacity: opacity))
    }

    /// A profile that specifies how to interpret a color value for display.
    public enum RGBColorSpace: Hashable, Sendable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    /// Creates a constant color from red, green, and blue component values in a colour space.
    /// Linear components are converted to sRGB; Display P3 components are used as sRGB
    /// (Docs/elements/Paint.md).
    public init(_ colorSpace: RGBColorSpace, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let convert = colorSpace == .sRGBLinear ? Self.sRGBComponent(fromLinear:) : { $0 }
        self.init(storage: .rgba(red: convert(red), green: convert(green), blue: convert(blue), opacity: opacity))
    }

    /// Creates a constant grayscale color in a colour space.
    public init(_ colorSpace: RGBColorSpace, white: Double, opacity: Double = 1) {
        self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
    }

    /// The sRGB transfer function applied to a linear component.
    package static func sRGBComponent(fromLinear value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * _pow(clamped, 1 / 2.4) - 0.055
    }

    /// Multiplies the opacity of the color by the given amount.
    public func opacity(_ opacity: Double) -> Color {
        Color(storage: storage, opacityMultiplier: opacityMultiplier * opacity)
    }

    public static let red = Color(storage: .system(.red))
    public static let orange = Color(storage: .system(.orange))
    public static let yellow = Color(storage: .system(.yellow))
    public static let green = Color(storage: .system(.green))
    public static let mint = Color(storage: .system(.mint))
    public static let teal = Color(storage: .system(.teal))
    public static let cyan = Color(storage: .system(.cyan))
    public static let blue = Color(storage: .system(.blue))
    public static let indigo = Color(storage: .system(.indigo))
    public static let purple = Color(storage: .system(.purple))
    public static let pink = Color(storage: .system(.pink))
    public static let brown = Color(storage: .system(.brown))
    public static let white = Color(storage: .system(.white))
    public static let gray = Color(storage: .system(.gray))
    public static let black = Color(storage: .system(.black))
    public static let clear = Color(storage: .system(.clear))
    public static let primary = Color(storage: .system(.primary))
    public static let secondary = Color(storage: .system(.secondary))
    public static let accentColor = Color(storage: .system(.accentColor))
}

extension Color: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Color>) -> TypedNode<Color> {
        ColorNode(context)
    }
}
