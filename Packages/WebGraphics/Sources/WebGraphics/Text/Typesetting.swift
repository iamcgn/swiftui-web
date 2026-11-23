// Typesetting an attributed string into lines one at a time, as Core Text's typesetter does
// for a text engine that lays out its own lines (Runestone's code editor): each grapheme
// cluster's advance in its run's font, the line breaks that fit a width, the caret offset of a
// string index and the index nearest a point. The `CoreText` shadow (Packages/Shadows) gives
// these Core Text's names on wasm; UIKit draws a typeset line into its graphics context.
//
// Advances come from the text engine the host installed (`TextTypesetter.engine`), one cluster
// at a time, so a line's width is the sum of its clusters' advances and their kerning. A tab
// advances to the paragraph's next tab stop, a line separator has no width. Text runs left to
// right: there is no bidirectional reordering here.
import WebFoundation

/// A font an attributed string holds under `NSFont` (UIKit's `UIFont`): what the text engine
/// measures and the line metrics a typeset line reports.
public protocol TypesettingFont {
    var typesettingFont: ResolvedFont { get }
    /// Above the baseline, positive.
    var typesettingAscent: CGFloat { get }
    /// Below the baseline, positive.
    var typesettingDescent: CGFloat { get }
    var typesettingLeading: CGFloat { get }
}

/// A paragraph style an attributed string holds under `NSParagraphStyle`: where its tabs stop.
public protocol TypesettingParagraphStyle {
    /// The tab stops' locations, in order.
    var typesettingTabStops: [CGFloat] { get }
    /// The interval of the stops after the last one (0: none past them).
    var typesettingTabInterval: CGFloat { get }
}

/// One grapheme cluster of a typeset string: where it starts (in UTF-16 units), how many units
/// it spans, its advance and the run it belongs to.
public struct TypesetCluster: Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var advance: CGFloat
    public var run: Int
    public var isWhitespace: Bool
    public var isLineSeparator: Bool
    public var end: Int { location + length }
}

/// A range of an attributed string with one set of attributes, and that range's font.
public struct TypesetRun: @unchecked Sendable {
    public var location: Int
    public var length: Int
    public var attributes: [NSAttributedString.Key: Any]
    public var font: ResolvedFont
    public var ascent: CGFloat
    public var descent: CGFloat
    public var leading: CGFloat
    public var end: Int { location + length }
}

/// An attributed string measured cluster by cluster, from which lines are cut.
public final class TextTypesetter: @unchecked Sendable {
    /// The engine that measures clusters; the UIKit scene installs its own. Without one a
    /// cluster advances by 0.6 of its font's size. A typesetter measures on the main actor.
    nonisolated(unsafe) public static var engine: (any TextEngine)?

    /// Core Text's default font when a range names none (Helvetica 12; the system font here).
    public static let defaultFont = ResolvedFont(family: "system", size: 12, weight: .regular, italic: false, textStyle: nil)

    public let attributedString: NSAttributedString
    /// The string's UTF-16 units, which the string indices count.
    public let utf16: [UInt16]
    public var length: Int { utf16.count }
    public let runs: [TypesetRun]
    public let clusters: [TypesetCluster]

    public init(_ attributedString: NSAttributedString) {
        // The string as it is now: a mutable string the caller changes later keeps this layout.
        self.attributedString = NSAttributedString(attributedString: attributedString)
        let string = self.attributedString.string
        utf16 = Array(string.utf16)
        let length = utf16.count
        var runs: [TypesetRun] = []
        if length > 0 {
            self.attributedString.enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { attributes, range, _ in
                let font = attributes[NSAttributedString.Key("NSFont")] as? TypesettingFont
                let resolved = font?.typesettingFont ?? TextTypesetter.defaultFont
                runs.append(TypesetRun(location: range.location, length: range.length, attributes: attributes, font: resolved,
                                       ascent: font?.typesettingAscent ?? resolved.size * 0.77,
                                       descent: font?.typesettingDescent ?? resolved.size * 0.23,
                                       leading: font?.typesettingLeading ?? 0))
            }
        }
        self.runs = runs

        var clusters: [TypesetCluster] = []
        var measured: [ResolvedFont: [String: CGFloat]] = [:]
        var runIndex = 0
        var location = 0
        var x: CGFloat = 0
        for character in string {
            let units = character.utf16.count
            while runIndex < runs.count - 1, runs[runIndex].end <= location { runIndex += 1 }
            let run = runs.isEmpty ? nil : runs[runIndex]
            let font = run?.font ?? TextTypesetter.defaultFont
            let isSeparator = character.isNewline
            let isWhitespace = character.isWhitespace
            var advance: CGFloat
            if isSeparator {
                advance = 0
            } else if character == "\t" {
                advance = Self.tabStop(after: x, style: run?.attributes[NSAttributedString.Key("NSParagraphStyle")] as? TypesettingParagraphStyle) - x
            } else {
                let text = String(character)
                if let known = measured[font]?[text] {
                    advance = known
                } else {
                    advance = Self.measure(text, font: font)
                    measured[font, default: [:]][text] = advance
                }
                if let kern = run?.attributes[NSAttributedString.Key("NSKern")] {
                    advance += Self.number(kern)
                }
            }
            clusters.append(TypesetCluster(location: location, length: units, advance: advance, run: runIndex,
                                           isWhitespace: isWhitespace, isLineSeparator: isSeparator))
            location += units
            x = isSeparator ? 0 : x + advance
        }
        self.clusters = clusters
    }

    /// Text engines measure on the main actor, where a page's (and UIKit's) drawing runs.
    private static func measure(_ text: String, font: ResolvedFont) -> CGFloat {
        MainActor.assumeIsolated {
            guard let engine else { return font.size * 0.6 }
            // A line reports the ink of its last line, which a space has none of: a space's
            // advance is what it adds between two letters.
            if text.allSatisfy(\.isWhitespace) {
                return max(0, width(of: "a" + text + "a", font: font, engine: engine) - width(of: "aa", font: font, engine: engine))
            }
            return width(of: text, font: font, engine: engine)
        }
    }

    @MainActor private static func width(of text: String, font: ResolvedFont, engine: any TextEngine) -> CGFloat {
        engine.layout(text, font: font, width: nil).lines.first?.width ?? 0
    }

    private static func number(_ value: Any) -> CGFloat {
        switch value {
        case let value as CGFloat: return value
        case let value as Double: return CGFloat(value)
        case let value as Float: return CGFloat(value)
        case let value as Int: return CGFloat(value)
        case let value as NSNumber: return CGFloat(value.doubleValue)
        default: return 0
        }
    }

    /// The next tab stop after `x`: the paragraph's stops, then its interval, else every 28
    /// points (Core Text's default stops are 28 points apart).
    static func tabStop(after x: CGFloat, style: TypesettingParagraphStyle?) -> CGFloat {
        if let stop = style?.typesettingTabStops.first(where: { $0 > x + 0.001 }) { return stop }
        let interval = style.map { $0.typesettingTabInterval > 0 ? $0.typesettingTabInterval : ($0.typesettingTabStops.isEmpty ? 28 : 0) } ?? 28
        guard interval > 0 else { return x }
        return ((x / interval).rounded(.down) + 1) * interval
    }

    /// A cluster's advance where it lands at `x` from its line's start: a tab reaches the next
    /// stop from there, so breaking and laying out a line that starts mid-paragraph agree.
    func advance(of cluster: TypesetCluster, at x: CGFloat) -> CGFloat {
        guard cluster.length == 1, utf16[cluster.location] == 0x09 else { return cluster.advance }
        let style = runs.isEmpty ? nil : runs[cluster.run].attributes[NSAttributedString.Key("NSParagraphStyle")] as? TypesettingParagraphStyle
        return Self.tabStop(after: x, style: style) - x
    }

    /// The index of the cluster that starts at or contains `location`.
    public func clusterIndex(at location: Int) -> Int {
        var low = 0, high = clusters.count
        while low < high {
            let mid = (low + high) / 2
            if clusters[mid].end <= location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// How many UTF-16 units from `start` fit in `width`, whole clusters only: at least one
    /// cluster when any remains. A line separator ends the line after itself.
    public func clusterBreak(from start: Int, width: CGFloat) -> Int {
        guard start < length else { return 0 }
        var index = clusterIndex(at: start)
        var x: CGFloat = 0
        var end = start
        while index < clusters.count {
            let cluster = clusters[index]
            if cluster.isLineSeparator { return cluster.end - start }
            let advance = self.advance(of: cluster, at: x)
            if end > start, x + advance > width + 0.001 { break }
            x += advance
            end = cluster.end
            index += 1
        }
        return end - start
    }

    /// How many UTF-16 units from `start` fit in `width`, breaking after a space or a hyphen
    /// when one fits: trailing spaces stay on the line however wide they are. With no break
    /// that fits, the clusters that fit.
    public func lineBreak(from start: Int, width: CGFloat) -> Int {
        guard start < length else { return 0 }
        var index = clusterIndex(at: start)
        var x: CGFloat = 0
        var lastBreak: Int?
        while index < clusters.count {
            let cluster = clusters[index]
            if cluster.isLineSeparator { return cluster.end - start }
            let advance = self.advance(of: cluster, at: x)
            if cluster.isWhitespace {
                x += advance
                lastBreak = cluster.end
                index += 1
                continue
            }
            if x + advance > width + 0.001, cluster.location > start {
                if let lastBreak { return lastBreak - start }
                return clusterBreak(from: start, width: width)
            }
            x += advance
            if breaksAfter(cluster) { lastBreak = cluster.end }
            index += 1
        }
        return length - start
    }

    /// A hyphen, an en dash or a slash lets the line break after it.
    private func breaksAfter(_ cluster: TypesetCluster) -> Bool {
        guard cluster.length == 1 else { return false }
        let unit = utf16[cluster.location]
        return unit == 0x2D || unit == 0x2013 || unit == 0x2F
    }

    /// The line covering `location..<location+length` (a length of 0 runs to the end).
    public func line(location: Int, length requested: Int, offset: CGFloat = 0) -> TypesetLine {
        let start = max(0, min(location, length))
        let end = requested > 0 ? min(length, start + requested) : length
        return TypesetLine(typesetter: self, location: start, length: end - start, offset: offset)
    }
}

/// A line cut from a typesetter: its clusters' x positions, its runs and its metrics.
public struct TypesetLine: @unchecked Sendable {
    /// A piece of the line in one run's attributes.
    public struct Run: @unchecked Sendable {
        public var location: Int
        public var length: Int
        public var attributes: [NSAttributedString.Key: Any]
        public var font: ResolvedFont
        public var ascent: CGFloat
        public var descent: CGFloat
        public var leading: CGFloat
        /// The run's clusters: where each starts on the line, its advance, its string index.
        public var positions: [CGFloat]
        public var advances: [CGFloat]
        public var indices: [Int]
        public var x: CGFloat { positions.first ?? 0 }
        public var width: CGFloat { advances.reduce(0, +) }
        public var text: String
    }

    public let location: Int
    public let length: Int
    public let runs: [Run]
    /// The caret offset of each cluster boundary, from the line's start: `edges[i]` is where
    /// cluster `i` of the line starts and the last is the line's end.
    public let edges: [CGFloat]
    /// The string index at each edge.
    public let edgeIndices: [Int]
    public let width: CGFloat
    public let trailingWhitespaceWidth: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    public let leading: CGFloat

    init(typesetter: TextTypesetter, location: Int, length: Int, offset: CGFloat) {
        self.location = location
        self.length = length
        var runs: [Run] = []
        var edges: [CGFloat] = [offset]
        var edgeIndices: [Int] = [location]
        var x = offset
        var trailing: CGFloat = 0
        let utf16 = typesetter.utf16
        var sourceRun = -1
        var index = typesetter.clusterIndex(at: location)
        let end = location + length
        while index < typesetter.clusters.count, typesetter.clusters[index].location < end {
            let cluster = typesetter.clusters[index]
            let source = typesetter.runs.isEmpty ? nil : typesetter.runs[cluster.run]
            if runs.isEmpty || cluster.run != sourceRun {
                sourceRun = cluster.run
                runs.append(Run(location: cluster.location, length: 0, attributes: source?.attributes ?? [:],
                                font: source?.font ?? TextTypesetter.defaultFont,
                                ascent: source?.ascent ?? 0, descent: source?.descent ?? 0, leading: source?.leading ?? 0,
                                positions: [], advances: [], indices: [], text: ""))
            }
            // A tab's advance depends on where it lands on this line.
            let advance = typesetter.advance(of: cluster, at: x - offset)
            var run = runs.removeLast()
            run.length += cluster.length
            run.positions.append(x)
            run.advances.append(advance)
            run.indices.append(cluster.location)
            run.text += String(decoding: utf16[cluster.location..<cluster.end], as: UTF16.self)
            runs.append(run)
            x += advance
            trailing = cluster.isWhitespace ? trailing + advance : 0
            edges.append(x)
            edgeIndices.append(cluster.end)
            index += 1
        }
        self.runs = runs
        self.edges = edges
        self.edgeIndices = edgeIndices
        width = x - offset
        trailingWhitespaceWidth = trailing
        let measured = runs.isEmpty ? Array(typesetter.runs.prefix(1)).map { ($0.ascent, $0.descent, $0.leading) } : runs.map { ($0.ascent, $0.descent, $0.leading) }
        ascent = measured.map(\.0).max() ?? TextTypesetter.defaultFont.size * 0.77
        descent = measured.map(\.1).max() ?? TextTypesetter.defaultFont.size * 0.23
        leading = measured.map(\.2).max() ?? 0
    }

    /// The caret offset of a string index: the start of the cluster it falls in, the line's
    /// end past it.
    public func offset(of stringIndex: Int) -> CGFloat {
        guard let last = edgeIndices.last, stringIndex < last else { return edges.last ?? 0 }
        guard stringIndex > location else { return edges[0] }
        var low = 0, high = edgeIndices.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if edgeIndices[mid] <= stringIndex { low = mid } else { high = mid - 1 }
        }
        return edges[low]
    }

    /// The string index of the caret boundary nearest to `x`.
    public func stringIndex(at x: CGFloat) -> Int {
        guard edges.count > 1 else { return location }
        if x <= edges[0] { return edgeIndices[0] }
        if x >= edges[edges.count - 1] { return edgeIndices[edgeIndices.count - 1] }
        for index in 1..<edges.count where x < edges[index] {
            return x - edges[index - 1] < edges[index] - x ? edgeIndices[index - 1] : edgeIndices[index]
        }
        return edgeIndices[edgeIndices.count - 1]
    }
}

/// A graphics context a typeset line draws into (UIKit's `CGContext`): at its text position,
/// which moves past what it draws.
@preconcurrency @MainActor
public protocol TypesetLineDrawing: AnyObject {
    func drawTypesetLine(_ line: TypesetLine)
    /// Draws the run's glyphs (clusters) in `glyphs`.
    func drawTypesetRun(_ run: TypesetLine.Run, glyphs: Range<Int>)
}
