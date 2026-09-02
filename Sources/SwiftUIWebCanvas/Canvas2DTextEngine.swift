#if os(WASI)
import JavaScriptKit
import SwiftUIWebCore

/// Text engine backed by Canvas2D `measureText` for advances and the measured macOS font table
/// for line heights, baselines and spacing (`SystemFontMetrics`). Line breaking, truncation and
/// line spacing follow SwiftUI's measured rules in `TextLayouter`.
@MainActor
final class Canvas2DTextEngine: TextEngine {
    private let context: JSObject
    private let bridge: JSObject
    private var widthCache: [String: CGFloat] = [:]
    private let profile = PlatformProfile.macOS

    init(context: JSObject, bridge: JSObject) {
        self.context = context
        self.bridge = bridge
    }

    /// Unrounded advance of `text` in `font` (rounding to the half point happens per line).
    private func width(of text: String, font: ResolvedFont) -> CGFloat {
        let css = DisplayListEncoder.cssFont(DisplayFont(font))
        let key = css + "|" + text
        if let cached = widthCache[key] { return cached }
        let measured = bridge.measure!(context, css, text).number ?? 0
        widthCache[key] = measured
        return measured
    }

    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width maxWidth: CGFloat?) -> TextLayout {
        let layouter = TextLayouter(measure: { [unowned self] text, font in self.width(of: text, font: font) },
                                    metrics: { [profile] font in profile.systemFontMetrics(for: font) })
        return layouter.layout(runs, options: options, width: maxWidth)
    }

    func metrics(for font: ResolvedFont) -> FontMetrics {
        profile.systemFontMetrics(for: font).fontMetrics
    }
}
#endif
