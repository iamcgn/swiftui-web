#if !os(WASI)
import Foundation
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
