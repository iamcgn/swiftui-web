/// Greedy paragraph layout for engines that can measure advances but not break lines
/// (Canvas2D `measureText`; tests with a synthetic measurer). Reproduces the rules measured from
/// SwiftUI on macOS (`Docs/elements/Text.md`):
///
/// - a line breaks after a space; trailing spaces hang, so a candidate line fits if its drawn
///   width is within the proposal, but the width it reports includes the trailing space (capped
///   at the proposal);
/// - a word wider than the proposal wraps by character (a zero proposal gives one character per
///   line), and a line never reports more than the proposal;
/// - widths are rounded up to the half point; the multi-line pitch is the line height rounded up
///   plus `lineSpacing`;
/// - `lineLimit` truncates the last permitted line with an ellipsis at the head, middle or tail,
///   cutting at character granularity;
/// - `"\n"` forces a break;
/// - a line with several fonts takes the tallest run's line height and baseline.
public struct TextLayouter {
    /// Unrounded advance width of `string` set in `font`.
    public var measure: (String, ResolvedFont) -> CGFloat
    /// Line metrics of a font.
    public var metrics: (ResolvedFont) -> SystemFontMetrics

    public init(measure: @escaping (String, ResolvedFont) -> CGFloat, metrics: @escaping (ResolvedFont) -> SystemFontMetrics) {
        self.measure = measure
        self.metrics = metrics
    }

    public static let ellipsis = "\u{2026}"

    public func layout(_ runs: [StyledRun], options: TextLayoutOptions, width maxWidth: CGFloat?) -> TextLayout {
        let string = runs.map(\.string).joined()
        let chars = Array(string)
        var runOf: [Int] = []
        runOf.reserveCapacity(chars.count)
        for (index, run) in runs.enumerated() { runOf += Array(repeating: index, count: run.string.count) }
        let fonts = runs.map(\.font)
        let firstFont = fonts.first ?? ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

        func half(_ w: CGFloat) -> CGFloat { (w * 2).rounded(.up) / 2 }
        func isSpace(_ c: Character) -> Bool { c == " " || c == "\n" }
        /// Segments of [lo, hi) by run.
        func segments(_ lo: Int, _ hi: Int) -> [(text: String, run: Int)] {
            var result: [(String, Int)] = []
            var start = lo
            while start < hi {
                let run = runOf[start]
                var end = start
                while end < hi, runOf[end] == run { end += 1 }
                result.append((String(chars[start..<end]), run))
                start = end
            }
            return result
        }
        func raw(_ lo: Int, _ hi: Int) -> CGFloat {
            segments(lo, hi).reduce(0) { $0 + measure($1.text, fonts[$1.run]) }
        }
        /// End of the drawn part of [lo, hi): trailing spaces and newlines are not drawn.
        func inkEnd(_ lo: Int, _ hi: Int) -> Int {
            var end = hi
            while end > lo, isSpace(chars[end - 1]) { end -= 1 }
            return end
        }

        struct Piece { var lo: Int; var hi: Int; var width: CGFloat; var inkWidth: CGFloat; var fragments: [TextLayout.Fragment]; var runsShown: [Int] }
        func plainPiece(_ lo: Int, _ hi: Int, limit: CGFloat?) -> Piece {
            let ink = inkEnd(lo, hi)
            // A hard-broken or final line reports its ink; a wrapped line includes its trailing space.
            let reportEnd = (hi < chars.count && chars[hi - 1] == " ") ? hi : ink
            var reported = half(raw(lo, reportEnd))
            if let limit { reported = min(reported, limit) }
            var fragments: [TextLayout.Fragment] = []
            var x: CGFloat = 0
            for segment in segments(lo, ink) {
                let w = measure(segment.text, fonts[segment.run])
                fragments.append(.init(text: segment.text, run: segment.run, x: x, width: w))
                x += w
            }
            let runsShown = ink > lo ? Array(Set(runOf[lo..<ink])).sorted() : [runOf.indices.contains(lo) ? runOf[lo] : 0]
            return Piece(lo: lo, hi: hi, width: reported, inkWidth: half(x), fragments: fragments, runsShown: runsShown)
        }

        /// The rest of the text from `lo`, truncated to fit `limit` with an ellipsis.
        func truncatedPiece(_ lo: Int, limit: CGFloat) -> Piece {
            let end = chars.count
            func ellipsisWidth(_ run: Int) -> CGFloat { measure(Self.ellipsis, fonts[run]) }
            var fragments: [TextLayout.Fragment] = []
            var x: CGFloat = 0
            func append(_ text: String, _ run: Int) {
                let w = measure(text, fonts[run])
                fragments.append(.init(text: text, run: run, x: x, width: w))
                x += w
            }
            func appendSegments(_ a: Int, _ b: Int) { for s in segments(a, b) { append(s.text, s.run) } }
            switch options.truncationMode {
            case .tail:
                var keep = lo
                var k = lo + 1
                while k <= end {
                    let run = runOf[k - 1]
                    if half(raw(lo, k) + ellipsisWidth(run)) <= limit { keep = k; k += 1 } else { break }
                }
                let run = keep > lo ? runOf[keep - 1] : runOf[min(lo, end - 1)]
                appendSegments(lo, keep)
                append(Self.ellipsis, run)
            case .head:
                var keep = end
                var k = end - 1
                while k >= lo {
                    let run = runOf[k]
                    if half(ellipsisWidth(run) + raw(k, end)) <= limit { keep = k; k -= 1 } else { break }
                }
                let run = keep < end ? runOf[keep] : runOf[min(lo, end - 1)]
                append(Self.ellipsis, run)
                appendSegments(keep, end)
            case .middle:
                var a = lo, b = end
                var growPrefix = true
                while a < b {
                    let (na, nb) = growPrefix ? (a + 1, b) : (a, b - 1)
                    let run = growPrefix ? runOf[na - 1] : runOf[nb]
                    if half(raw(lo, na) + ellipsisWidth(run) + raw(nb, end)) <= limit {
                        a = na; b = nb
                        growPrefix.toggle()
                    } else if growPrefix {
                        // The prefix cannot grow; try the suffix once more, then stop.
                        let run2 = runOf[b - 1]
                        if b - 1 > a, half(raw(lo, a) + ellipsisWidth(run2) + raw(b - 1, end)) <= limit { b -= 1 } else { break }
                    } else {
                        break
                    }
                }
                let run = a > lo ? runOf[a - 1] : (b < end ? runOf[b] : runOf[min(lo, end - 1)])
                appendSegments(lo, a)
                append(Self.ellipsis, run)
                appendSegments(b, end)
            }
            let width = min(half(x), limit)
            let shown = Array(Set(fragments.map(\.run))).sorted()
            return Piece(lo: lo, hi: end, width: width, inkWidth: width, fragments: fragments, runsShown: shown)
        }

        // Break the text into pieces (lines before vertical placement).
        var pieces: [Piece] = []
        if chars.isEmpty {
            pieces.append(Piece(lo: 0, hi: 0, width: 0, inkWidth: 0, fragments: [], runsShown: [0]))
        } else {
            var lo = 0
            let limitCount = options.lineLimit.map { max($0, 1) }
            while lo < chars.count {
                // Candidate ends: after each space (the space counts towards the width), at a
                // newline, or at the end of the text. The last candidate that fits wins.
                var hi = lo
                var best: Int? = nil
                while hi < chars.count {
                    hi += 1
                    guard hi == chars.count || isSpace(chars[hi - 1]) else { continue }
                    // Trailing spaces hang: only the drawn part has to fit.
                    if let maxWidth, half(raw(lo, inkEnd(lo, hi))) > maxWidth { break }
                    best = hi
                    if chars[hi - 1] == "\n" { break }
                }
                var end: Int
                if let best {
                    end = best
                } else if let maxWidth {
                    // Not even the first word fits: wrap by character, at least one per line.
                    end = lo + 1
                    while end < chars.count, !isSpace(chars[end - 1]), !isSpace(chars[end]), half(raw(lo, end + 1)) <= maxWidth { end += 1 }
                    // Spaces after the piece hang off its end rather than starting a line.
                    while end < chars.count, isSpace(chars[end]) { end += 1 }
                } else {
                    end = chars.count
                }
                let isLastPermitted = limitCount.map { pieces.count == $0 - 1 } ?? false
                if isLastPermitted, end < chars.count, let maxWidth {
                    pieces.append(truncatedPiece(lo, limit: maxWidth))
                    lo = chars.count
                    break
                }
                pieces.append(plainPiece(lo, end, limit: maxWidth))
                lo = end
                if let limitCount, pieces.count >= limitCount, lo < chars.count {
                    // Over the limit with no width to truncate against (unspecified proposal): the
                    // remaining text is dropped.
                    break
                }
            }
        }
        if let limit = options.lineLimit, options.reservesSpace, pieces.count < limit {
            let last = pieces.last!
            for _ in pieces.count..<limit {
                pieces.append(Piece(lo: last.hi, hi: last.hi, width: 0, inkWidth: 0, fragments: [], runsShown: last.runsShown))
            }
        }

        // Vertical placement: each line takes the tallest font on it.
        var lines: [TextLayout.Line] = []
        var top: CGFloat = 0
        var widest: CGFloat = 0
        var height: CGFloat = 0
        for (index, piece) in pieces.enumerated() {
            let lineFonts = piece.runsShown.map { fonts.indices.contains($0) ? fonts[$0] : firstFont }
            let lineMetrics = lineFonts.map(metrics)
            let lineHeight = lineMetrics.map(\.lineHeight).max() ?? 0
            let baseline = lineMetrics.map(\.baseline).max() ?? 0
            let start = string.index(string.startIndex, offsetBy: piece.lo)
            let end = string.index(string.startIndex, offsetBy: piece.hi)
            lines.append(TextLayout.Line(range: start..<end, width: piece.width, inkWidth: piece.inkWidth,
                                         baseline: top + baseline, fragments: piece.fragments))
            widest = max(widest, piece.width)
            height = top + lineHeight
            if index < pieces.count - 1 { top += lineHeight.rounded(.up) + options.lineSpacing }
        }
        return TextLayout(size: CGSize(width: widest, height: height),
                          firstBaseline: lines.first?.baseline ?? 0, lastBaseline: lines.last?.baseline ?? 0, lines: lines)
    }
}
