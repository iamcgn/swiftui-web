// Core Text's typesetter, lines and runs on wasm, for an app that lays out its own lines
// (Runestone's code editor): a typesetter made from an attributed string suggests where lines
// break for a width and cuts lines, and a line reports its width and metrics, the caret offset
// of a string index, the index nearest a point and its runs' positions and advances.
// WebGraphics' `TextTypesetter` measures the string with the page's text engine;
// `CTLineDraw` draws a line into UIKit's graphics context at its text position. Each glyph
// here is one grapheme cluster, and every run runs left to right.
#if os(WASI)
@_exported import WebFoundation
import WebGraphics

/// A typesetter for one attributed string.
public final class CTTypesetter: @unchecked Sendable {
    let typesetter: TextTypesetter
    init(_ string: NSAttributedString) { typesetter = TextTypesetter(string) }
}

/// One line of typeset text.
public final class CTLine: @unchecked Sendable {
    let line: TypesetLine
    let glyphRuns: [CTRun]
    init(_ line: TypesetLine) {
        self.line = line
        glyphRuns = line.runs.map(CTRun.init)
    }
}

/// A piece of a line in one set of attributes.
public final class CTRun: @unchecked Sendable {
    let run: TypesetLine.Run
    init(_ run: TypesetLine.Run) { self.run = run }
}

/// What is unusual about a run's glyphs.
public struct CTRunStatus: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let noStatus = CTRunStatus([])
    public static let rightToLeft = CTRunStatus(rawValue: 1 << 0)
    public static let nonMonotonic = CTRunStatus(rawValue: 1 << 1)
    public static let hasNonIdentityMatrix = CTRunStatus(rawValue: 1 << 2)
}

/// How a line is truncated (`CTLineCreateTruncatedLine`).
public enum CTLineTruncationType: UInt32, Sendable {
    case start = 0, end = 1, middle = 2
}

/// Which bounds `CTLineGetBoundsWithOptions` reports.
public struct CTLineBoundsOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let excludeTypographicLeading = CTLineBoundsOptions(rawValue: 1 << 0)
    public static let excludeTypographicShifts = CTLineBoundsOptions(rawValue: 1 << 1)
    public static let useHangingPunctuation = CTLineBoundsOptions(rawValue: 1 << 2)
    public static let useGlyphPathBounds = CTLineBoundsOptions(rawValue: 1 << 3)
    public static let useOpticalBounds = CTLineBoundsOptions(rawValue: 1 << 4)
    public static let includeLanguageExtents = CTLineBoundsOptions(rawValue: 1 << 5)
}

// MARK: Typesetter

public func CTTypesetterCreateWithAttributedString(_ string: CFAttributedString) -> CTTypesetter {
    CTTypesetter(string)
}

public func CTTypesetterCreateWithAttributedStringAndOptions(_ string: CFAttributedString, _ options: CFDictionary?) -> CTTypesetter? {
    CTTypesetter(string)
}

/// The line covering `stringRange` (a length of 0 runs to the end of the string).
public func CTTypesetterCreateLine(_ typesetter: CTTypesetter, _ stringRange: CFRange) -> CTLine {
    CTLine(typesetter.typesetter.line(location: stringRange.location, length: stringRange.length))
}

/// The line covering `stringRange`, its positions starting at `offset`.
public func CTTypesetterCreateLineWithOffset(_ typesetter: CTTypesetter, _ stringRange: CFRange, _ offset: Double) -> CTLine {
    CTLine(typesetter.typesetter.line(location: stringRange.location, length: stringRange.length, offset: CGFloat(offset)))
}

/// How many UTF-16 units from `startIndex` a line `width` wide takes, breaking between words.
public func CTTypesetterSuggestLineBreak(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double) -> CFIndex {
    typesetter.typesetter.lineBreak(from: startIndex, width: CGFloat(width))
}

public func CTTypesetterSuggestLineBreakWithOffset(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double, _ offset: Double) -> CFIndex {
    typesetter.typesetter.lineBreak(from: startIndex, width: CGFloat(width))
}

/// How many UTF-16 units from `startIndex` a line `width` wide takes, breaking between clusters.
public func CTTypesetterSuggestClusterBreak(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double) -> CFIndex {
    typesetter.typesetter.clusterBreak(from: startIndex, width: CGFloat(width))
}

public func CTTypesetterSuggestClusterBreakWithOffset(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double, _ offset: Double) -> CFIndex {
    typesetter.typesetter.clusterBreak(from: startIndex, width: CGFloat(width))
}

// MARK: Lines

/// One line of the whole string, unbroken.
public func CTLineCreateWithAttributedString(_ attrString: CFAttributedString) -> CTLine {
    CTLine(TextTypesetter(attrString).line(location: 0, length: 0))
}

public func CTLineGetStringRange(_ line: CTLine) -> CFRange {
    CFRange(location: line.line.location, length: line.line.length)
}

public func CTLineGetGlyphCount(_ line: CTLine) -> CFIndex {
    line.line.runs.reduce(0) { $0 + $1.advances.count }
}

/// The line's runs, as `CTRun`s (`CTLineGetGlyphRuns(line) as? [CTRun]`).
public func CTLineGetGlyphRuns(_ line: CTLine) -> CFArray {
    line.glyphRuns
}

/// The line's width; its ascent, descent and leading through the pointers given.
public func CTLineGetTypographicBounds(_ line: CTLine, _ ascent: UnsafeMutablePointer<CGFloat>?,
                                       _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    ascent?.pointee = line.line.ascent
    descent?.pointee = line.line.descent
    leading?.pointee = line.line.leading
    return Double(line.line.width)
}

/// The line's typographic box: from the descent below the baseline to the ascent above it.
public func CTLineGetBoundsWithOptions(_ line: CTLine, _ options: CTLineBoundsOptions) -> CGRect {
    let leading = options.contains(.excludeTypographicLeading) ? 0 : line.line.leading
    let x = line.line.edges.first ?? 0
    return CGRect(x: x, y: -line.line.descent, width: line.line.width,
                  height: line.line.ascent + line.line.descent + leading)
}

public func CTLineGetTrailingWhitespaceWidth(_ line: CTLine) -> Double {
    Double(line.line.trailingWhitespaceWidth)
}

/// The caret offset of `charIndex` from the line's origin; the secondary offset is the same,
/// with no bidirectional text.
public func CTLineGetOffsetForStringIndex(_ line: CTLine, _ charIndex: CFIndex, _ secondaryOffset: UnsafeMutablePointer<CGFloat>?) -> CGFloat {
    let offset = line.line.offset(of: charIndex)
    secondaryOffset?.pointee = offset
    return offset
}

/// The string index of the caret boundary nearest `position`'s x.
public func CTLineGetStringIndexForPosition(_ line: CTLine, _ position: CGPoint) -> CFIndex {
    line.line.stringIndex(at: position.x)
}

/// Calls `block` with each cluster's caret offset, its string index, whether the offset is
/// its leading edge, and a stop flag.
public func CTLineEnumerateCaretOffsets(_ line: CTLine, _ block: (Double, CFIndex, Bool, UnsafeMutablePointer<Bool>) -> Void) {
    var stop = false
    for run in line.line.runs {
        for (index, start) in run.indices.enumerated() {
            block(Double(run.positions[index]), start, true, &stop)
            if stop { return }
            block(Double(run.positions[index] + run.advances[index]), start, false, &stop)
            if stop { return }
        }
    }
}

/// The x where a line `flushWidth` wide starts it: 0 flush left, the rest of the width flush
/// right, half of it centred (`flushFactor` 0, 1 and 0.5).
public func CTLineGetPenOffsetForFlush(_ line: CTLine, _ flushFactor: CGFloat, _ flushWidth: Double) -> Double {
    let rest = flushWidth - Double(line.line.width - line.line.trailingWhitespaceWidth)
    return max(0, rest * Double(min(max(flushFactor, 0), 1)))
}

// MARK: Runs

public func CTRunGetGlyphCount(_ run: CTRun) -> CFIndex { run.run.advances.count }

public func CTRunGetStringRange(_ run: CTRun) -> CFRange { CFRange(location: run.run.location, length: run.run.length) }

public func CTRunGetStatus(_ run: CTRun) -> CTRunStatus { [] }

public func CTRunGetTextMatrix(_ run: CTRun) -> CGAffineTransform { .identity }

/// The run's attributes, keyed by their names.
public func CTRunGetAttributes(_ run: CTRun) -> CFDictionary {
    Dictionary(uniqueKeysWithValues: run.run.attributes.map { ($0.key.rawValue, $0.value) })
}

/// The glyphs `range` covers (a length of 0 runs to the end of the run).
private func _glyphs(_ run: CTRun, _ range: CFRange) -> Range<Int> {
    let count = run.run.advances.count
    let start = min(max(0, range.location), count)
    let end = range.length > 0 ? min(count, start + range.length) : count
    return start..<end
}

public func CTRunGetPositions(_ run: CTRun, _ range: CFRange, _ buffer: UnsafeMutablePointer<CGPoint>) {
    for (offset, index) in _glyphs(run, range).enumerated() { buffer[offset] = CGPoint(x: run.run.positions[index], y: 0) }
}

public func CTRunGetAdvances(_ run: CTRun, _ range: CFRange, _ buffer: UnsafeMutablePointer<CGSize>) {
    for (offset, index) in _glyphs(run, range).enumerated() { buffer[offset] = CGSize(width: run.run.advances[index], height: 0) }
}

public func CTRunGetStringIndices(_ run: CTRun, _ range: CFRange, _ buffer: UnsafeMutablePointer<CFIndex>) {
    for (offset, index) in _glyphs(run, range).enumerated() { buffer[offset] = run.run.indices[index] }
}

/// The width of the glyphs `range` covers; the run's ascent, descent and leading through the
/// pointers given.
public func CTRunGetTypographicBounds(_ run: CTRun, _ range: CFRange, _ ascent: UnsafeMutablePointer<CGFloat>?,
                                      _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    ascent?.pointee = run.run.ascent
    descent?.pointee = run.run.descent
    leading?.pointee = run.run.leading
    return Double(_glyphs(run, range).reduce(CGFloat(0)) { $0 + run.run.advances[$1] })
}

// MARK: Drawing

/// Draws the line into `context` at its text position (Core Text's y is up, so a context
/// flipped for UIKit draws it upright), and moves the text position past it.
@preconcurrency @MainActor
public func CTLineDraw(_ line: CTLine, _ context: some TypesetLineDrawing) {
    context.drawTypesetLine(line.line)
}

/// Draws the glyphs of `range` of the run (a length of 0 draws them all).
@preconcurrency @MainActor
public func CTRunDraw(_ run: CTRun, _ context: some TypesetLineDrawing, _ range: CFRange) {
    context.drawTypesetRun(run.run, glyphs: _glyphs(run, range))
}
#endif
