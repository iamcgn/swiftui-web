/// A font with every environment dependency resolved, as the text engine consumes it.
public struct ResolvedFont: Hashable, Sendable {
    public var family: String          // "system", "system-rounded", "system-serif", "system-monospaced", or a custom name
    public var size: CGFloat
    public var weight: FontWeight
    public var italic: Bool
    /// The text style this font derives from. Text-style fonts have their own line metrics
    /// (`.body` is 13 pt with an 18.5 pt line; `.system(size: 13)` has a 16 pt line), so the
    /// style survives weight and design overrides.
    public var textStyle: FontTextStyle?
    /// Whether `weight` overrides the text style's default weight.
    public var weightOverridden: Bool
    /// The platform profile the font was resolved for (`PlatformProfile.name`): its line
    /// metrics come from that platform's table, whichever engine measures the glyphs.
    public var profile: String

    public init(family: String, size: CGFloat, weight: FontWeight, italic: Bool,
                textStyle: FontTextStyle?, weightOverridden: Bool = false, profile: String = "macOS") {
        self.family = family
        self.size = size
        self.weight = weight
        self.italic = italic
        self.textStyle = textStyle
        self.weightOverridden = weightOverridden
        self.profile = profile
    }

    public var designName: String {
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


// MARK: Text scale

extension ResolvedFont {
    /// The font `textScale(.secondary)` draws with, and the tracking it adds after every glyph
    /// (measured with a `TextRenderer` on macOS 26, 2026-09-05). The scale factor and tracking
    /// depend on the weight and fade with size: constant up to 17 pt, interpolated linearly to
    /// their 70 pt values, constant beyond; the line height stays the base font's. Serif,
    /// monospaced and custom families are not scaled.
    public var secondaryScaled: (font: ResolvedFont, tracking: CGFloat)? {
        guard family == "system" || family == "system-rounded" else { return nil }
        // (factor at ≤ 17 pt, factor at ≥ 70 pt, tracking at ≤ 17 pt) per weight.
        let table: [Int: (CGFloat, CGFloat, CGFloat)] = [
            100: (0.8, 0.46, 0.16), 200: (0.8, 0.46, 0.15), 300: (0.8, 0.46, 0.1854), 400: (0.8, 0.46, 0.25),
            500: (0.8, 0.48, 0.4147), 600: (0.84, 0.49, 0), 700: (0.85, 0.5, -0.05), 800: (0.85, 0.52, 0.2), 900: (0.87, 0.55, 0.35),
        ]
        let entry = table[weight.value] ?? table[400]!
        let t = min(1, max(0, (size - 17) / 53))
        let factor = entry.0 - (entry.0 - entry.1) * t
        let tracking = (family == "system-rounded" ? 0.03 : entry.2) * (1 - t)
        var scaled = self
        scaled.size = size * factor
        // SwiftUI's scaled face also raises the weight axis (about 510 for regular), so its
        // glyphs run wider than the plain font at that size: 2.4 % (3.3 % in the display
        // optical size, 1.7 % medium, 3.4 % bold and up), spread over the glyphs as spacing.
        let gain: CGFloat = weight.value >= 700 ? 0.034 : weight.value >= 500 ? 0.017 : scaled.size >= 20 ? 0.033 : 0.024
        return (scaled, tracking + 0.5 * gain * scaled.size)
    }
}
