#if os(WASI)
import JavaScriptKit
import SwiftUIWebCore

/// Text engine backed by Canvas2D `measureText` for widths and the measured macOS font table
/// for line heights, baselines and spacing (`SystemFontMetrics`). Line breaking is greedy on
/// spaces (DOM-assisted breaks are Phase 2).
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

    private func width(of text: String, css: String) -> CGFloat {
        let key = css + "|" + text
        if let cached = widthCache[key] { return cached }
        let measured = bridge.measure!(context, css, text).number ?? 0
        // SwiftUI reports text widths on a half-point grid (every golden width is a multiple of 0.5).
        let width = (measured * 2).rounded(.up) / 2
        widthCache[key] = width
        return width
    }

    func layout(_ string: String, font: ResolvedFont, width maxWidth: CGFloat?) -> TextLayout {
        let css = DisplayListEncoder.cssFont(DisplayFont(font))
        let metrics = profile.systemFontMetrics(for: font)
        let single = width(of: string, css: css)
        if maxWidth == nil || single <= maxWidth! || !string.contains(" ") {
            return TextLayout(size: CGSize(width: single, height: metrics.lineHeight),
                              firstBaseline: metrics.baseline, lastBaseline: metrics.baseline,
                              lines: [TextLayout.Line(range: string.startIndex..<string.endIndex, width: single, baseline: metrics.baseline)])
        }
        // Greedy wrap on spaces. SwiftUI's rule (fixture text/wrapped): a line fits only if its
        // width *including the trailing space* is within the limit, and that width is what the
        // text reports (137 for a 133.5 pt line + 3.5 pt space). A word wider than the limit
        // gets its own line.
        let limit = maxWidth!
        let pitch = metrics.lineHeight.rounded(.up)   // multi-line pitch: body 18.5 → 19
        let words = string.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var lines: [(text: String, width: CGFloat, reported: CGFloat)] = []
        var current = ""
        func flush(final: Bool) {
            let ink = width(of: current, css: css)
            let reported = final ? ink : width(of: current + " ", css: css)
            lines.append((current, ink, reported))
            current = ""
        }
        for (index, word) in words.enumerated() {
            let candidate = current.isEmpty ? word : current + " " + word
            let isLast = index == words.count - 1
            let fits = width(of: isLast ? candidate : candidate + " ", css: css) <= limit
            if fits || current.isEmpty {
                current = candidate
            } else {
                flush(final: false)
                current = word
            }
        }
        flush(final: true)
        var offset = string.startIndex
        var layoutLines: [TextLayout.Line] = []
        for (index, line) in lines.enumerated() {
            let end = string.index(offset, offsetBy: line.text.count)
            layoutLines.append(TextLayout.Line(range: offset..<end, width: line.width,
                                               baseline: metrics.baseline + CGFloat(index) * pitch))
            offset = end < string.endIndex ? string.index(after: end) : end
        }
        let widest = lines.map(\.reported).max() ?? 0
        let height = metrics.lineHeight + CGFloat(lines.count - 1) * pitch
        return TextLayout(size: CGSize(width: widest, height: height),
                          firstBaseline: metrics.baseline, lastBaseline: layoutLines.last?.baseline ?? metrics.baseline,
                          lines: layoutLines)
    }

    func metrics(for font: ResolvedFont) -> FontMetrics {
        profile.systemFontMetrics(for: font).fontMetrics
    }
}
#endif
