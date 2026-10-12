// A text engine over cairo's toy font API (pf-linux): advances from `cairo_text_extents`
// on the system's fonts, line metrics from the measured font tables (as the canvas engine
// does), lines broken by the shared `TextLayouter`. Approximate: the glyphs are whatever
// fontconfig resolves "sans-serif" to, so widths differ from SF's; the recorded engine
// (`WebGraphicsHeadless`) stays the one the goldens are checked with.
#if canImport(CCairo)
import CCairo
import WebFoundation
import WebGraphics

@MainActor
public final class CairoTextEngine: TextEngine {
    /// A scratch surface the extents are measured on.
    private let surface: OpaquePointer
    private let context: OpaquePointer
    private var widths: [String: CGFloat] = [:]

    public init() {
        surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1)
        context = cairo_create(surface)
    }

    /// The unrounded advance of `text` in `font`.
    public func advance(of text: String, font: ResolvedFont) -> CGFloat {
        let key = font.key + "|" + text
        if let cached = widths[key] { return cached }
        let family: String
        switch font.family {
        case "system", "system-rounded": family = "sans-serif"
        case "system-serif": family = "serif"
        case "system-monospaced": family = "monospace"
        default: family = font.family
        }
        cairo_select_font_face(context, family, font.italic ? CAIRO_FONT_SLANT_ITALIC : CAIRO_FONT_SLANT_NORMAL, font.weight.value >= 600 ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(context, Double(font.size))
        var extents = cairo_text_extents_t()
        cairo_text_extents(context, text, &extents)
        let width = CGFloat(extents.x_advance)
        widths[key] = width
        return width
    }

    public func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let layouter = TextLayouter(measure: { [unowned self] text, font in self.advance(of: text, font: font) },
                                    metrics: { font in SystemFontMetricsTables.systemFontMetrics(for: font) })
        return layouter.layout(runs, options: options, width: width)
    }

    public func metrics(for font: ResolvedFont) -> FontMetrics {
        SystemFontMetricsTables.systemFontMetrics(for: font).fontMetrics
    }
}
#endif
