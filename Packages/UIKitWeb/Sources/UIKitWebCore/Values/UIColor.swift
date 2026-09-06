// UIColor (Docs/elements/UIKit/UIColor.md): a colour with a value per appearance. System
// colours carry the values sampled from the Catalyst goldens (`ios/color/system`,
// `ios/dark/system-colors`; the same palette SwiftUIWeb's iOS profile reads), and labels keep
// the alphas those goldens show.

/// An object that stores colour data and sometimes opacity.
public final class UIColor: Hashable, @unchecked Sendable {
    /// The colour in the light and dark appearances.
    public let light: RGBA
    public let dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    public convenience init(_ rgba: RGBA) {
        self.init(light: rgba, dark: rgba)
    }

    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(RGBA(red: red, green: green, blue: blue, alpha: alpha))
    }

    public convenience init(white: CGFloat, alpha: CGFloat) {
        self.init(RGBA(red: white, green: white, blue: white, alpha: alpha))
    }

    public convenience init(displayP3Red red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// A colour that resolves per trait collection (both appearances are evaluated now).
    public convenience init(dynamicProvider: (UITraitCollection) -> UIColor) {
        let light = dynamicProvider(UITraitCollection(userInterfaceStyle: .light))
        let dark = dynamicProvider(UITraitCollection(userInterfaceStyle: .dark))
        self.init(light: light.light, dark: dark.dark)
    }

    public convenience init(cgColor: CGColor) {
        self.init(RGBA(cgColor: cgColor) ?? .black)
    }

    /// Hue, saturation and brightness in 0…1.
    public convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let h = (hue - hue.rounded(.down)) * 6
        let sector = Int(h.rounded(.down)) % 6
        let f = h - h.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch sector {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    public static func == (lhs: UIColor, rhs: UIColor) -> Bool { lhs.light == rhs.light && lhs.dark == rhs.dark }
    public func hash(into hasher: inout Hasher) { hasher.combine(light); hasher.combine(dark) }

    /// The colour for a trait collection's appearance.
    public func resolvedColor(with traitCollection: UITraitCollection) -> UIColor {
        UIColor(rgba(for: traitCollection.userInterfaceStyle))
    }

    /// The display value for an appearance.
    public func rgba(for style: UIUserInterfaceStyle) -> RGBA {
        style == .dark ? dark : light
    }

    /// The light value as a `CGColor` (a dynamic colour resolves to its light value here, as
    /// UIKit does for `cgColor` outside a trait environment).
    public var cgColor: CGColor { light.cgColor }

    public func withAlphaComponent(_ alpha: CGFloat) -> UIColor {
        UIColor(light: RGBA(red: light.red, green: light.green, blue: light.blue, alpha: alpha),
                dark: RGBA(red: dark.red, green: dark.green, blue: dark.blue, alpha: alpha))
    }

    /// The light value's components; false when the colour is not RGB (never, here).
    public func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        red?.pointee = light.red
        green?.pointee = light.green
        blue?.pointee = light.blue
        alpha?.pointee = light.alpha
        return true
    }

    // MARK: Fixed colours

    public static let clear = UIColor(.clear)
    public static let black = UIColor(.black)
    public static let white = UIColor(.white)
    public static let darkGray = UIColor(white: 1.0 / 3, alpha: 1)
    public static let lightGray = UIColor(white: 2.0 / 3, alpha: 1)
    public static let gray = UIColor(white: 0.5, alpha: 1)
    public static let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    public static let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    public static let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    public static let cyan = UIColor(red: 0, green: 1, blue: 1, alpha: 1)
    public static let yellow = UIColor(red: 1, green: 1, blue: 0, alpha: 1)
    public static let magenta = UIColor(red: 1, green: 0, blue: 1, alpha: 1)
    public static let orange = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    public static let purple = UIColor(red: 0.5, green: 0, blue: 0.5, alpha: 1)
    public static let brown = UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)

    // MARK: System colours (sampled from the Catalyst goldens; macOS 26's palette)

    public static let systemRed = UIColor(light: RGBA(r: 255, g: 56, b: 60), dark: RGBA(r: 255, g: 66, b: 69))
    public static let systemOrange = UIColor(light: RGBA(r: 255, g: 141, b: 40), dark: RGBA(r: 255, g: 146, b: 48))
    public static let systemYellow = UIColor(light: RGBA(r: 255, g: 204, b: 0), dark: RGBA(r: 255, g: 214, b: 0))
    public static let systemGreen = UIColor(light: RGBA(r: 52, g: 199, b: 89), dark: RGBA(r: 48, g: 209, b: 88))
    public static let systemMint = UIColor(light: RGBA(r: 0, g: 200, b: 179), dark: RGBA(r: 0, g: 218, b: 195))
    public static let systemTeal = UIColor(light: RGBA(r: 0, g: 195, b: 208), dark: RGBA(r: 0, g: 210, b: 224))
    public static let systemCyan = UIColor(light: RGBA(r: 0, g: 192, b: 232), dark: RGBA(r: 60, g: 211, b: 254))
    public static let systemBlue = UIColor(light: RGBA(r: 0, g: 136, b: 255), dark: RGBA(r: 0, g: 145, b: 255))
    public static let systemIndigo = UIColor(light: RGBA(r: 97, g: 85, b: 245), dark: RGBA(r: 109, g: 124, b: 255))
    public static let systemPurple = UIColor(light: RGBA(r: 203, g: 48, b: 224), dark: RGBA(r: 219, g: 52, b: 242))
    public static let systemPink = UIColor(light: RGBA(r: 255, g: 45, b: 85), dark: RGBA(r: 255, g: 55, b: 95))
    public static let systemBrown = UIColor(light: RGBA(r: 172, g: 127, b: 94), dark: RGBA(r: 183, g: 138, b: 102))
    public static let systemGray = UIColor(light: RGBA(r: 142, g: 142, b: 147), dark: RGBA(r: 152, g: 152, b: 157))
    public static let systemGray2 = UIColor(light: RGBA(r: 174, g: 174, b: 178), dark: RGBA(r: 99, g: 99, b: 102))
    public static let systemGray3 = UIColor(light: RGBA(r: 199, g: 199, b: 204), dark: RGBA(r: 72, g: 72, b: 74))
    public static let systemGray4 = UIColor(light: RGBA(r: 209, g: 209, b: 214), dark: RGBA(r: 58, g: 58, b: 60))
    public static let systemGray5 = UIColor(light: RGBA(r: 229, g: 229, b: 234), dark: RGBA(r: 44, g: 44, b: 46))
    public static let systemGray6 = UIColor(light: RGBA(r: 242, g: 242, b: 247), dark: RGBA(r: 28, g: 28, b: 30))

    /// The label colours keep the alphas the Catalyst goldens show (216/255 for the primary).
    public static let label = UIColor(light: RGBA(r: 0, g: 0, b: 0, a: 216.0 / 255), dark: RGBA(r: 255, g: 255, b: 255, a: 216.0 / 255))
    public static let secondaryLabel = UIColor(light: RGBA(r: 0, g: 0, b: 0, a: 0.5), dark: RGBA(r: 255, g: 255, b: 255, a: 140.0 / 255))
    public static let tertiaryLabel = UIColor(light: RGBA(r: 0, g: 0, b: 0, a: 0.26), dark: RGBA(r: 255, g: 255, b: 255, a: 0.25))
    public static let quaternaryLabel = UIColor(light: RGBA(r: 0, g: 0, b: 0, a: 0.1), dark: RGBA(r: 255, g: 255, b: 255, a: 0.1))
    public static let placeholderText = UIColor(light: RGBA(r: 189, g: 189, b: 190), dark: RGBA(r: 235, g: 235, b: 245, a: 0.3))
    public static let link = UIColor(light: RGBA(r: 0, g: 104, b: 218), dark: RGBA(r: 65, g: 156, b: 255))
    public static let separator = UIColor(light: RGBA(r: 0, g: 0, b: 0, a: 25.0 / 255), dark: RGBA(r: 255, g: 255, b: 255, a: 25.0 / 255))
    public static let opaqueSeparator = UIColor(light: RGBA(r: 198, g: 198, b: 200), dark: RGBA(r: 56, g: 56, b: 58))
    public static let systemBackground = UIColor(light: .white, dark: .black)
    public static let secondarySystemBackground = UIColor(light: RGBA(r: 242, g: 242, b: 247), dark: RGBA(r: 28, g: 28, b: 30))
    public static let tertiarySystemBackground = UIColor(light: .white, dark: RGBA(r: 44, g: 44, b: 46))
    public static let systemGroupedBackground = UIColor(light: RGBA(r: 235, g: 236, b: 236), dark: .black)
    public static let secondarySystemGroupedBackground = UIColor(light: .white, dark: RGBA(r: 28, g: 28, b: 30))
    public static let tertiarySystemGroupedBackground = UIColor(light: RGBA(r: 242, g: 242, b: 247), dark: RGBA(r: 44, g: 44, b: 46))
    public static let systemFill = UIColor(light: RGBA(r: 120, g: 120, b: 128, a: 0.2), dark: RGBA(r: 120, g: 120, b: 128, a: 0.36))
    public static let secondarySystemFill = UIColor(light: RGBA(r: 120, g: 120, b: 128, a: 0.16), dark: RGBA(r: 120, g: 120, b: 128, a: 0.32))
    public static let tertiarySystemFill = UIColor(light: RGBA(r: 118, g: 118, b: 128, a: 0.12), dark: RGBA(r: 118, g: 118, b: 128, a: 0.24))
    public static let quaternarySystemFill = UIColor(light: RGBA(r: 116, g: 116, b: 128, a: 0.08), dark: RGBA(r: 118, g: 118, b: 128, a: 0.18))
    /// The default tint: the system blue.
    public static let tintColor = systemBlue
}
