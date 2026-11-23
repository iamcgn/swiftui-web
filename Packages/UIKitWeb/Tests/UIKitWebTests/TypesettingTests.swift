// Core Text's typesetter over UIKit's fonts (Runestone's code editor lays out its own lines):
// clusters measured in their run's font, word and cluster breaks for a width, caret offsets
// and the index nearest a point, tab stops and kerning, and a typeset line drawn through the
// text matrix into a context flipped for Core Text.
import Testing
@testable import UIKitWebCore
import WebGraphics
import WebFoundation

@Suite @MainActor struct TypesettingTests {
    /// The synthetic engine advances every character by half its font's size: 10 at 20 pt.
    private func typesetter(_ string: NSAttributedString) -> TextTypesetter {
        UIKitScene.shared.textEngine = SyntheticTextEngine()
        return TextTypesetter(string)
    }

    private let font = UIFont.systemFont(ofSize: 20)

    @Test func breaksBetweenWordsAndClustersForAWidth() {
        let typesetter = typesetter(NSAttributedString(string: "hello world foo", attributes: [.font: font]))
        #expect(typesetter.clusters.map(\.advance) == Array(repeating: 10, count: 15))
        // "hello " is 60 wide and "w" still fits in 75, but "wo" doesn't: the line breaks after the space.
        #expect(typesetter.lineBreak(from: 0, width: 75) == 6)
        #expect(typesetter.lineBreak(from: 6, width: 75) == 6)
        #expect(typesetter.lineBreak(from: 12, width: 75) == 3)
        #expect(typesetter.clusterBreak(from: 0, width: 75) == 7)
        // A word wider than the line breaks between clusters, and at least one cluster goes.
        #expect(typesetter.lineBreak(from: 0, width: 35) == 3)
        #expect(typesetter.clusterBreak(from: 0, width: 4) == 1)
        #expect(typesetter.lineBreak(from: 15, width: 75) == 0)
    }

    @Test func aLineReportsOffsetsIndicesAndMetrics() {
        let typesetter = typesetter(NSAttributedString(string: "hello world", attributes: [.font: font]))
        let line = typesetter.line(location: 0, length: 6)
        #expect(line.width == 60)
        #expect(line.trailingWhitespaceWidth == 10)
        #expect(line.offset(of: 3) == 30)
        #expect(line.offset(of: 6) == 60)
        #expect(line.offset(of: 40) == 60)
        #expect(line.stringIndex(at: 34) == 3)
        #expect(line.stringIndex(at: 36) == 4)
        #expect(line.stringIndex(at: -5) == 0)
        #expect(line.stringIndex(at: 500) == 6)
        #expect(line.ascent == font.ascender)
        #expect(line.descent == -font.descender)
        // The second line's offsets start at its own origin and count the whole string's indices.
        let second = typesetter.line(location: 6, length: 0)
        #expect(second.length == 5)
        #expect(second.offset(of: 8) == 20)
        #expect(second.stringIndex(at: 21) == 8)
    }

    @Test func tabsStopAtTheParagraphsStopsAndKerningWidensClusters() {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = 40
        let tabbed = typesetter(NSAttributedString(string: "a\tb\tc", attributes: [.font: font, .paragraphStyle: style]))
        let line = tabbed.line(location: 0, length: 0)
        #expect(line.offset(of: 2) == 40)
        #expect(line.offset(of: 4) == 80)
        #expect(line.width == 90)
        // UIKit's default stops are every 28 points.
        let plain = typesetter(NSAttributedString(string: "a\tb", attributes: [.font: font])).line(location: 0, length: 0)
        #expect(plain.offset(of: 2) == 28)
        let kerned = typesetter(NSAttributedString(string: "ab", attributes: [.font: font, .kern: 2])).line(location: 0, length: 0)
        #expect(kerned.width == 24)
    }

    @Test func aTabOnALineThatStartsMidParagraphBreaksWhereItLands() {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = 40
        let tabbed = typesetter(NSAttributedString(string: "zzzz a\tb", attributes: [.font: font, .paragraphStyle: style]))
        // From the wrapped line's start, "a" ends at 10 and the tab reaches the stop at 40, so
        // "b" (to 50) doesn't fit in 45, whatever the tab measured from the paragraph's start.
        #expect(tabbed.lineBreak(from: 5, width: 45) == 2)
        #expect(tabbed.clusterBreak(from: 5, width: 45) == 2)
        let line = tabbed.line(location: 5, length: 3)
        #expect(line.offset(of: 7) == 40)
        #expect(line.width == 50)
    }

    @Test func runsFollowTheAttributes() {
        let string = NSMutableAttributedString(string: "ab", attributes: [.font: font])
        string.append(NSAttributedString(string: "cd", attributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.red]))
        let line = typesetter(string).line(location: 0, length: 0)
        #expect(line.runs.count == 2)
        #expect(line.runs.map(\.location) == [0, 2])
        #expect(line.runs[1].positions == [20, 25])
        #expect(line.runs[1].advances == [5, 5])
        #expect(line.runs[1].text == "cd")
        #expect(line.width == 30)
        #expect(line.ascent == font.ascender)
    }

    @Test func aLineDrawsUprightInAContextFlippedForCoreText() {
        let line = typesetter(NSAttributedString(string: "hi\tyo", attributes: [.font: font])).line(location: 0, length: 0)
        let context = UIGraphicsRecordingContext(origin: .zero, scale: 2)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: 24)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: 0, y: 5)
        context.drawTypesetLine(line)
        let texts = context.commands.compactMap { command -> (String, CGPoint)? in
            if case .drawText(let text, _, let origin, _) = command { return (text, origin) } else { return nil }
        }
        // The tab leaves a gap: the text after it starts at the next stop.
        #expect(texts.map(\.0) == ["hi", "yo"])
        #expect(texts.map(\.1) == [CGPoint(x: 0, y: 0), CGPoint(x: 28, y: 0)])
        let transform = context.commands.compactMap { command -> CGAffineTransform? in
            if case .concat(let transform) = command { return transform } else { return nil }
        }.last
        // The baseline lands 5 points above the flipped context's bottom, and the glyphs' tops above it.
        #expect(CGPoint(x: 0, y: 0).applying(transform ?? .identity) == CGPoint(x: 0, y: 19))
        #expect(CGPoint(x: 0, y: -10).applying(transform ?? .identity).y == 9)
        #expect(context.textPosition == CGPoint(x: line.width, y: 5))
    }
}
