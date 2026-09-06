/// An environment-dependent font.
public struct Font: Hashable, Sendable {
    public typealias TextStyle = FontTextStyle
    public typealias Weight = FontWeight

    /// A design to use for fonts.
    public enum Design: Hashable, Sendable {
        case `default`, serif, rounded, monospaced
    }

    /// A width to use for fonts that have multiple widths.
    public struct Width: Hashable, Sendable {
        public var value: CGFloat
        public init(_ value: CGFloat) { self.value = value }
        public static let compressed = Width(0.8)
        public static let condensed = Width(0.9)
        public static let standard = Width(1)
        public static let expanded = Width(1.2)
    }

    /// The font's base provider before modifiers are applied.
    package enum Provider: Hashable, Sendable {
        case textStyle(TextStyle, design: Design?, weight: Weight?)
        case system(size: CGFloat, weight: Weight?, design: Design?)
        case custom(name: String, size: CGFloat, relativeTo: TextStyle?)
    }

    package struct Modifiers: Hashable, Sendable {
        package var weight: Weight?
        /// The bold *trait*: resolves to a weight that depends on the text style (decision 0010).
        package var bold = false
        package var italic = false
        package var monospacedDigit = false
        package var monospaced = false
        package var width: Width?
        package var leading: Leading?
        package var smallCaps = false
    }

    /// Line spacing adjustment.
    public enum Leading: Hashable, Sendable { case standard, tight, loose }

    package let provider: Provider
    package var modifiers = Modifiers()

    package init(provider: Provider) {
        self.provider = provider
    }

    // MARK: Text styles

    public static let largeTitle = Font(provider: .textStyle(.largeTitle, design: nil, weight: nil))
    public static let title = Font(provider: .textStyle(.title, design: nil, weight: nil))
    public static let title2 = Font(provider: .textStyle(.title2, design: nil, weight: nil))
    public static let title3 = Font(provider: .textStyle(.title3, design: nil, weight: nil))
    public static let headline = Font(provider: .textStyle(.headline, design: nil, weight: nil))
    public static let subheadline = Font(provider: .textStyle(.subheadline, design: nil, weight: nil))
    public static let body = Font(provider: .textStyle(.body, design: nil, weight: nil))
    public static let callout = Font(provider: .textStyle(.callout, design: nil, weight: nil))
    public static let footnote = Font(provider: .textStyle(.footnote, design: nil, weight: nil))
    public static let caption = Font(provider: .textStyle(.caption, design: nil, weight: nil))
    public static let caption2 = Font(provider: .textStyle(.caption2, design: nil, weight: nil))

    /// Gets a system font that uses the specified style, design, and weight.
    public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font {
        Font(provider: .textStyle(style, design: design, weight: weight))
    }

    /// Specifies a system font to use, along with the style, weight, and any design parameters.
    public static func system(size: CGFloat, weight: Weight? = nil, design: Design? = nil) -> Font {
        Font(provider: .system(size: size, weight: weight, design: design))
    }

    /// Create a custom font with the given name and size.
    public static func custom(_ name: String, size: CGFloat) -> Font {
        Font(provider: .custom(name: name, size: size, relativeTo: nil))
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: TextStyle) -> Font {
        Font(provider: .custom(name: name, size: size, relativeTo: textStyle))
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        Font(provider: .custom(name: name, size: fixedSize, relativeTo: nil))
    }

    // MARK: Modifiers

    public func weight(_ weight: Weight) -> Font { var f = self; f.modifiers.weight = weight; return f }
    /// `bold()` applies the bold *trait*. On macOS it resolves per text style (semibold for
    /// `.body`, bold for `.title`, heavy for `.headline`…) and to bold for point-size fonts
    /// (fixtures text/modifiers, text/bold-trait); see `PlatformProfile.TextStyleMetrics`.
    public func bold() -> Font { var f = self; f.modifiers.bold = true; return f }
    public func italic() -> Font { var f = self; f.modifiers.italic = true; return f }
    public func monospaced() -> Font { var f = self; f.modifiers.monospaced = true; return f }
    public func monospacedDigit() -> Font { var f = self; f.modifiers.monospacedDigit = true; return f }
    public func width(_ width: Width) -> Font { var f = self; f.modifiers.width = width; return f }
    public func leading(_ leading: Leading) -> Font { var f = self; f.modifiers.leading = leading; return f }
    public func smallCaps() -> Font { var f = self; f.modifiers.smallCaps = true; return f }
    public func lowercaseSmallCaps() -> Font { smallCaps() }
    public func uppercaseSmallCaps() -> Font { smallCaps() }
}

extension Font {
    /// Resolves the font for the platform profile (text style sizes/weights are per platform).
    package func resolve(profile: PlatformProfile) -> ResolvedFont {
        var family = "system"
        var size: CGFloat
        var weight = Font.Weight.regular
        var textStyle: Font.TextStyle?
        var weightOverridden = false
        func familyName(_ design: Design?) -> String {
            switch design {
            case nil, .default?: return "system"
            case .rounded?: return "system-rounded"
            case .serif?: return "system-serif"
            case .monospaced?: return "system-monospaced"
            }
        }
        switch provider {
        case .textStyle(let style, let design, let styleWeight):
            let metrics = profile.textStyle(style)
            size = metrics.size
            weight = styleWeight ?? metrics.weight
            weightOverridden = styleWeight != nil
            family = familyName(design)
            textStyle = style
        case .system(let s, let w, let design):
            size = s
            weight = w ?? .regular
            family = familyName(design)
        case .custom(let name, let s, _):
            family = name
            size = s
        }
        if let w = modifiers.weight {
            weight = w; weightOverridden = true
        } else if modifiers.bold {
            weight = profile.boldTraitWeight(for: textStyle); weightOverridden = true
        }
        if modifiers.monospaced { family = "system-monospaced" }
        return ResolvedFont(family: family, size: size, weight: weight, italic: modifiers.italic,
                            textStyle: textStyle, weightOverridden: weightOverridden, profile: profile.name)
    }
}

// MARK: Environment

package struct FontKey: EnvironmentKey {
    package static let defaultValue: Font? = nil
}

extension EnvironmentValues {
    /// The default font of this environment.
    public var font: Font? {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }
}

extension View {
    /// Sets the default font for text in this view.
    nonisolated public func font(_ font: Font?) -> some View {
        environment(\.font, font)
    }
}
