/// An environment-dependent font.
public struct Font: Hashable, Sendable {
    /// Dynamic text styles.
    public enum TextStyle: Hashable, Sendable, CaseIterable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    }

    /// A weight to use for fonts.
    public struct Weight: Hashable, Sendable {
        package let value: Int   // 100…900 in CSS terms
        package init(_ value: Int) { self.value = value }
        public static let ultraLight = Weight(100)
        public static let thin = Weight(200)
        public static let light = Weight(300)
        public static let regular = Weight(400)
        public static let medium = Weight(500)
        public static let semibold = Weight(600)
        public static let bold = Weight(700)
        public static let heavy = Weight(800)
        public static let black = Weight(900)
    }

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
    /// `bold()` applies the bold *trait*, which on macOS resolves to the semibold face
    /// (fixture text/modifiers: `Text.bold()` measures like `.fontWeight(.semibold)`).
    public func bold() -> Font { weight(PlatformMetrics.boldTraitWeight) }
    public func italic() -> Font { var f = self; f.modifiers.italic = true; return f }
    public func monospaced() -> Font { var f = self; f.modifiers.monospaced = true; return f }
    public func monospacedDigit() -> Font { var f = self; f.modifiers.monospacedDigit = true; return f }
    public func width(_ width: Width) -> Font { var f = self; f.modifiers.width = width; return f }
    public func leading(_ leading: Leading) -> Font { var f = self; f.modifiers.leading = leading; return f }
    public func smallCaps() -> Font { var f = self; f.modifiers.smallCaps = true; return f }
    public func lowercaseSmallCaps() -> Font { smallCaps() }
    public func uppercaseSmallCaps() -> Font { smallCaps() }
}

/// A font with every environment dependency resolved, as the text engine consumes it.
public struct ResolvedFont: Hashable, Sendable {
    public var family: String          // "system", "system-rounded", "system-serif", "system-monospaced", or a custom name
    public var size: CGFloat
    public var weight: Font.Weight
    public var italic: Bool
    /// The text style this font derives from. Text-style fonts have their own line metrics
    /// (`.body` is 13 pt with an 18.5 pt line; `.system(size: 13)` has a 16 pt line), so the
    /// style survives weight and design overrides.
    public var textStyle: Font.TextStyle?
    /// Whether `weight` overrides the text style's default weight.
    public var weightOverridden: Bool

    public init(family: String, size: CGFloat, weight: Font.Weight, italic: Bool,
                textStyle: Font.TextStyle?, weightOverridden: Bool = false) {
        self.family = family
        self.size = size
        self.weight = weight
        self.italic = italic
        self.textStyle = textStyle
        self.weightOverridden = weightOverridden
    }

    package var designName: String {
        switch family {
        case "system": return "default"
        case "system-rounded": return "rounded"
        case "system-serif": return "serif"
        case "system-monospaced": return "monospaced"
        default: return family
        }
    }

    /// Key used by the recorded metrics table and the fixture harness. Must match
    /// `FixtureFont.key` in Fixtures/Sources/TextMetricsRequests.swift:
    /// `style:<name>[:w<weight>][:<design>][:italic]` or `system:<size>:<weight>:<design>[:italic]`.
    public var key: String {
        let italicSuffix = italic ? ":italic" : ""
        if let textStyle {
            var key = "style:\(textStyle)"
            if weightOverridden { key += ":w\(weight.value)" }
            if designName != "default" { key += ":\(designName)" }
            return key + italicSuffix
        }
        let sizeText = size == size.rounded() ? "\(Int(size))" : "\(size)"
        return "system:\(sizeText):\(weight.value):\(designName)" + italicSuffix
    }
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
        if let w = modifiers.weight { weight = w; weightOverridden = true }
        if modifiers.monospaced { family = "system-monospaced" }
        return ResolvedFont(family: family, size: size, weight: weight, italic: modifiers.italic,
                            textStyle: textStyle, weightOverridden: weightOverridden)
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
