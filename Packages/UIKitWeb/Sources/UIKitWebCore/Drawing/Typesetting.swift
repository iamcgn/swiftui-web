// Typeset lines in UIKit (Core Text's `CTLineDraw` into a `CGContext`, Runestone's code
// editor): UIFont and NSParagraphStyle give WebGraphics' typesetter its fonts' metrics and the
// tab stops, the scene's text engine measures, and the graphics context draws a typeset line
// at its text position through its text matrix. Core Text's text space has y up, so a context
// flipped for it (`translateBy(0, height)`, `scaleBy(1, -1)`) draws the line upright.

extension UIFont: TypesettingFont {
    public var typesettingFont: ResolvedFont { resolved }
    public var typesettingAscent: CGFloat { ascender }
    public var typesettingDescent: CGFloat { -descender }
    public var typesettingLeading: CGFloat { leading }
}

extension NSParagraphStyle: TypesettingParagraphStyle {
    public var typesettingTabStops: [CGFloat] { tabStops.map(\.location) }
    public var typesettingTabInterval: CGFloat { defaultTabInterval }
}

extension UIGraphicsRecordingContext: TypesetLineDrawing {
    public func drawTypesetLine(_ line: TypesetLine) {
        draw(line.runs.map { ($0, 0..<$0.advances.count) }, ascent: line.ascent, descent: line.descent)
        textPosition.x += line.width
    }

    public func drawTypesetRun(_ run: TypesetLine.Run, glyphs: Range<Int>) {
        draw([(run, glyphs)], ascent: run.ascent, descent: run.descent)
    }

    /// Records the runs' glyphs in text space: each cluster that shows something, at its
    /// position on the baseline, in its run's font and foreground colour (black by default).
    private func draw(_ pieces: [(TypesetLine.Run, Range<Int>)], ascent: CGFloat, descent: CGFloat) {
        let appearance = UITraitCollection.current.userInterfaceStyle
        var commands: [DisplayCommand] = []
        var extent: CGRect?
        for (run, glyphs) in pieces where !glyphs.isEmpty {
            let color = (run.attributes[.foregroundColor] as? UIColor ?? .black).rgba(for: appearance).multiplyingAlpha(by: Double(currentAlpha))
            let font = DisplayFont(run.font)
            // Consecutive clusters draw as one piece of text, split where a tab or a line
            // separator leaves a gap.
            var text = "", start: CGFloat = 0, width: CGFloat = 0
            func flush() {
                guard !text.isEmpty else { return }
                commands.append(.drawText(text, font, origin: CGPoint(x: start, y: 0), color))
                let box = CGRect(x: start, y: -ascent, width: width, height: ascent + descent)
                extent = extent.map { $0.union(box) } ?? box
                text = ""
            }
            let clusters = Array(run.text)
            for index in glyphs {
                let cluster = index < clusters.count ? clusters[index] : " "
                if cluster == "\t" || cluster.isNewline {
                    flush()
                    continue
                }
                if text.isEmpty { start = run.positions[index]; width = 0 }
                text.append(cluster)
                width += run.advances[index]
            }
            flush()
        }
        guard let extent, !commands.isEmpty else { return }
        // Text space (y up) to user space: flip, then the text matrix, which carries the text position.
        let saved = ctm
        setTransformForText(CGAffineTransform(scaleX: 1, y: -1).concatenating(textMatrix).concatenating(saved))
        record(commands, bounds: extent.insetBy(dx: -2, dy: -2))
        setTransformForText(saved)
    }
}
