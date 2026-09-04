#if canImport(AppKit)
import AppKit
import CoreText
import SwiftUIWebCore

/// Text engine backed by CoreText for advances and the measured macOS font table for line
/// heights, baselines and spacing (`SystemFontMetrics`), so native layout matches the goldens
/// the way the browser engine does (decision 0005: Canvas2D advances equal CoreText's).
@MainActor
public final class CoreTextEngine: TextEngine {
    private var widthCache: [String: CGFloat] = [:]
    private var fontCache: [ResolvedFont: NSFont] = [:]
    private let profile = PlatformProfile.macOS

    public init() {}

    /// The AppKit font for a resolved font: the system font at the size and weight, with the
    /// rounded/serif/monospaced designs and the italic trait; custom families by name.
    public func nsFont(_ font: ResolvedFont) -> NSFont {
        if let cached = fontCache[font] { return cached }
        let weights: [Int: NSFont.Weight] = [100: .ultraLight, 200: .thin, 300: .light, 400: .regular, 500: .medium,
                                             600: .semibold, 700: .bold, 800: .heavy, 900: .black]
        let weight = weights[font.weight.value] ?? .regular
        var result: NSFont
        if font.family.hasPrefix("system") {
            result = NSFont.systemFont(ofSize: font.size, weight: weight)
            let designs: [String: NSFontDescriptor.SystemDesign] = ["rounded": .rounded, "serif": .serif, "monospaced": .monospaced]
            if let design = designs[font.designName], let descriptor = result.fontDescriptor.withDesign(design),
               let designed = NSFont(descriptor: descriptor, size: font.size) {
                result = designed
            }
        } else {
            result = NSFont(name: font.family, size: font.size) ?? NSFont.systemFont(ofSize: font.size, weight: weight)
        }
        if font.italic, let italic = NSFont(descriptor: result.fontDescriptor.withSymbolicTraits(.italic), size: font.size) {
            result = italic
        }
        fontCache[font] = result
        return result
    }

    /// The font with the display font's values (painting).
    public func nsFont(_ font: DisplayFont) -> NSFont {
        let weights: [Int: Font.Weight] = [100: .ultraLight, 200: .thin, 300: .light, 400: .regular, 500: .medium, 600: .semibold, 700: .bold, 800: .heavy, 900: .black]
        return nsFont(ResolvedFont(family: font.family, size: font.size, weight: weights[font.weight] ?? .regular, italic: font.italic, textStyle: nil))
    }

    /// The advance of `text` in a display font (the host's caret).
    public func advance(of text: String, font: DisplayFont) -> CGFloat {
        let weights: [Int: Font.Weight] = [100: .ultraLight, 200: .thin, 300: .light, 400: .regular, 500: .medium, 600: .semibold, 700: .bold, 800: .heavy, 900: .black]
        return width(of: text, font: ResolvedFont(family: font.family, size: font.size, weight: weights[font.weight] ?? .regular, italic: font.italic, textStyle: nil))
    }

    /// Unrounded advance of `text` in `font` (rounding to the half point happens per line).
    private func width(of text: String, font: ResolvedFont) -> CGFloat {
        let key = font.key + "|" + text
        if let cached = widthCache[key] { return cached }
        let attributed = NSAttributedString(string: text, attributes: [.font: nsFont(font)])
        let line = CTLineCreateWithAttributedString(attributed)
        let measured = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        widthCache[key] = measured
        return measured
    }

    public func layout(_ runs: [StyledRun], options: TextLayoutOptions, width maxWidth: CGFloat?) -> TextLayout {
        let layouter = TextLayouter(measure: { [unowned self] text, font in self.width(of: text, font: font) },
                                    metrics: { [profile] font in profile.systemFontMetrics(for: font) })
        return layouter.layout(runs, options: options, width: maxWidth)
    }

    public func metrics(for font: ResolvedFont) -> FontMetrics {
        profile.systemFontMetrics(for: font).fontMetrics
    }
}
#endif
