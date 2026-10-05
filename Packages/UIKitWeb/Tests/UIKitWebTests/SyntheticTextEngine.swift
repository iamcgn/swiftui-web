import WebGraphics

/// A deterministic engine for behavior tests whose strings or scaled fonts have no recordings.
/// Uniform character advances exercise wrapping and painting; fidelity tests keep the goldens.
@MainActor
final class SyntheticTextEngine: TextEngine {
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let layouter = TextLayouter(
            measure: { text, font in CGFloat(text.count) * font.size / 2 },
            metrics: { SystemFontMetricsTables.systemFontMetrics(for: $0) })
        return layouter.layout(runs, options: options, width: width)
    }

    func metrics(for font: ResolvedFont) -> FontMetrics {
        SystemFontMetricsTables.systemFontMetrics(for: font).fontMetrics
    }
}
