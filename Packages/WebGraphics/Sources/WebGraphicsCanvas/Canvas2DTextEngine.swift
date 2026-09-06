#if os(WASI)
import JavaScriptKit
import WebGraphics

/// Text engine backed by Canvas2D `measureText` for advances and the measured macOS font table
/// for line heights, baselines and spacing (`SystemFontMetrics`). Line breaking, truncation and
/// line spacing follow SwiftUI's measured rules in `TextLayouter`.
@MainActor
public final class Canvas2DTextEngine: TextEngine {
    private let context: JSObject
    private let bridge: JSObject
    private var widthCache: [String: CGFloat] = [:]
    private var cssFonts: [ResolvedFont: String] = [:]

    public init(context: JSObject, bridge: JSObject) {
        self.context = context
        self.bridge = bridge
    }

    /// Unrounded advance of `text` in `font` (rounding to the half point happens per line).
    private func width(of text: String, font: ResolvedFont) -> CGFloat {
        let css: String
        if let known = cssFonts[font] {
            css = known
        } else {
            css = DisplayListEncoder.cssFont(DisplayFont(font))
            cssFonts[font] = css
        }
        let key = css + "|" + text
        if let cached = widthCache[key] { return cached }
        let measured = bridge.measure!(context, css, text).number ?? 0
        widthCache[key] = measured
        return measured
    }

    public func layout(_ runs: [StyledRun], options: TextLayoutOptions, width maxWidth: CGFloat?) -> TextLayout {
        let layouter = TextLayouter(measure: { [unowned self] text, font in self.width(of: text, font: font) },
                                    metrics: { font in SystemFontMetricsTables.systemFontMetrics(for: font) })
        return layouter.layout(runs, options: options, width: maxWidth)
    }

    public func metrics(for font: ResolvedFont) -> FontMetrics {
        SystemFontMetricsTables.systemFontMetrics(for: font).fontMetrics
    }
}
#endif
