// Custom fonts (`Font.custom`, Docs/elements/Text.md "Custom fonts"): the line metrics of the
// font files an app bundles, registered from the asset catalog by whoever installs it, and the
// `SystemFontMetrics` the layouter derives from them at a size.

/// The font files known to the process, by the names `Font.custom` uses.
public enum CustomFontRegistry {
    nonisolated(unsafe) private static var fonts: [String: FontResource] = [:]

    /// Registers the catalog's fonts under their PostScript, full and family names.
    public static func register(_ catalog: AssetCatalog) {
        for font in catalog.fonts.values {
            fonts[font.postScriptName] = font
            fonts[font.family] = font
        }
    }

    public static func font(named name: String) -> FontResource? { fonts[name] }

    /// The line metrics of a custom font at `size`: the ascent and descent of its `hhea` table
    /// scaled to the size and each rounded, the line their sum (plus the line gap), the baseline
    /// the rounded ascent. Measured on SwiftUI at twenty sizes of Abel (`text/custom-font`,
    /// 2026-10-03): 15 pt gives 15 + 4 = 19 where the unrounded sum, 19.1, would round up to 20.
    public static func metrics(for font: ResolvedFont) -> SystemFontMetrics? {
        guard let resource = fonts[font.family] else { return nil }
        let scale = font.size / CGFloat(resource.unitsPerEm)
        let ascent = CGFloat(resource.ascender) * scale
        let descent = -CGFloat(resource.descender) * scale
        let gap = CGFloat(resource.lineGap) * scale
        let unrounded = ascent + descent + gap
        let baseline = ascent.rounded()
        let lineHeight = baseline + descent.rounded() + gap.rounded()
        return SystemFontMetrics(lineHeight: lineHeight, baseline: baseline, spacingBelow: descent, spacingAbove: 0, textToText: 0,
                                 linePitch: lineHeight, unroundedLineHeight: unrounded,
                                 capHeight: CGFloat(resource.capHeight) * scale, xHeight: CGFloat(resource.xHeight) * scale,
                                 underlineOffset: -CGFloat(resource.underlinePosition) * scale, underlineThickness: CGFloat(resource.underlineThickness) * scale)
    }
}
