// Phase 2 Text completeness: the greedy layouter (wrapping, character wrapping, line limit and
// truncation, line spacing, mixed fonts), the recorded-metrics key convention and concatenation.
import Testing
import SwiftUI
import SwiftUIWebHeadless

/// A synthetic measurer: every character is 10 points wide, the ellipsis 5, in every font;
/// 13 pt fonts have a 16 pt line (baseline 13), 26 pt fonts a 38 pt line (baseline 29).
private func layouter() -> TextLayouter {
    TextLayouter(
        measure: { text, _ in text.reduce(0) { $0 + ($1 == "\u{2026}" ? 5 : 10) } },
        metrics: { font in
            font.size > 13
                ? SystemFontMetrics(lineHeight: 38, baseline: 29, spacingBelow: 0, spacingAbove: 0, textToText: 0)
                : SystemFontMetrics(lineHeight: 16, baseline: 13, spacingBelow: 0, spacingAbove: 0, textToText: 0)
        })
}

private let small = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
private let large = ResolvedFont(family: "system", size: 26, weight: .regular, italic: false, textStyle: .largeTitle)

@Suite struct TextLayoutTests {
    private func lay(_ s: String, width: CGFloat?, options: TextLayoutOptions = .default) -> TextLayout {
        layouter().layout([StyledRun(s, font: small)], options: options, width: width)
    }
    private func texts(_ layout: TextLayout) -> [String] { layout.lines.map { $0.fragments.map(\.text).joined() } }

    @Test func singleLineWhenItFits() {
        let l = lay("Hello world", width: nil)
        #expect(l.size == CGSize(width: 110, height: 16))
        #expect(l.firstBaseline == 13 && l.lastBaseline == 13)
        #expect(texts(l) == ["Hello world"])
        #expect(lay("Hello world", width: 110).lines.count == 1)
    }

    @Test func wrapsAfterSpacesCountingTheTrailingSpace() {
        // "Hello " is 60 wide, "Hello world" 110: at 100 the first line is "Hello " (reported 60).
        let l = lay("Hello world", width: 100)
        #expect(texts(l) == ["Hello", "world"])
        #expect(l.lines[0].width == 60 && l.lines[0].inkWidth == 50)
        #expect(l.size == CGSize(width: 60, height: 32))
        #expect(l.lines[1].baseline == 29)
        // At 55 the trailing space hangs beyond the proposal; the line reports the proposal.
        #expect(texts(lay("Hello world", width: 55)) == ["Hello", "world"])
        #expect(lay("Hello world", width: 55).lines[0].width == 55)
    }

    @Test func wordsWiderThanTheProposalWrapByCharacter() {
        let l = lay("Hello", width: 25)
        #expect(texts(l) == ["He", "ll", "o"])
        #expect(l.size.width == 20)
        // A zero proposal gives one character per line and reports no width.
        let zero = lay("Hello", width: 0)
        #expect(zero.lines.count == 5 && zero.size.width == 0 && zero.size.height == 80)
        // Spaces hang off the preceding character instead of taking lines of their own.
        #expect(lay("ab cd", width: 0).lines.count == 4)
    }

    @Test func newlinesForceBreaks() {
        let l = lay("a b\ncd", width: nil)
        #expect(texts(l) == ["a b", "cd"])
        #expect(l.lines[0].width == 30)
    }

    @Test func lineLimitTruncatesTheLastLine() {
        let s = "one two three four"   // 180 wide
        let tail = lay(s, width: 100, options: TextLayoutOptions(lineLimit: 1))
        #expect(texts(tail) == ["one two t…"])   // 9 chars (90) + 5 = 95 ≤ 100
        #expect(tail.size == CGSize(width: 95, height: 16))
        let head = lay(s, width: 100, options: TextLayoutOptions(lineLimit: 1, truncationMode: .head))
        #expect(texts(head) == ["…hree four"])
        let middle = lay(s, width: 100, options: TextLayoutOptions(lineLimit: 1, truncationMode: .middle))
        #expect(texts(middle) == ["one t…four"])
        #expect(texts(lay(s, width: 100, options: TextLayoutOptions(lineLimit: 2))) == ["one two", "three four"])   // fits exactly
        let two = lay(s, width: 95, options: TextLayoutOptions(lineLimit: 2))
        #expect(texts(two) == ["one two", "three fou…"])
        // A limit above the line count changes nothing; reservesSpace pads the height.
        #expect(lay(s, width: 100, options: TextLayoutOptions(lineLimit: 5)).lines.count == 2)
        let reserved = lay("one", width: 100, options: TextLayoutOptions(lineLimit: 3, reservesSpace: true))
        #expect(reserved.size == CGSize(width: 30, height: 48) && reserved.lines.count == 3)
    }

    @Test func lineSpacingAddsToThePitch() {
        let l = lay("Hello world", width: 100, options: TextLayoutOptions(lineSpacing: 4))
        #expect(l.size.height == 36)   // 16 + 4 + 16
        #expect(l.lines[1].baseline == 33)   // 13 + (16 + 4)
    }

    @Test func mixedFontsShareOneLineWithTheTallestMetrics() {
        let l = layouter().layout([StyledRun("Big ", font: large), StyledRun("small", font: small)], options: .default, width: nil)
        #expect(l.lines.count == 1 && l.size == CGSize(width: 90, height: 38) && l.firstBaseline == 29)
        #expect(l.lines[0].fragments.map(\.text) == ["Big ", "small"])
        #expect(l.lines[0].fragments.map(\.x) == [0, 40])
        // Wrapping across a run boundary keeps the fragments in their fonts.
        let wrapped = layouter().layout([StyledRun("Big ", font: large), StyledRun("small", font: small)], options: .default, width: 60)
        #expect(texts(wrapped) == ["Big", "small"])
        #expect(wrapped.lines[1].fragments.first?.run == 1)
        #expect(wrapped.size.height == 54)   // a large line (38), then a small one (16)
    }

    @Test func recordedKeysFollowTheHarnessConvention() {
        let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
        #expect(TextMetricsKey.make(runs: [StyledRun("Hi", font: body)], options: .default, width: nil) == "style:body||Hi")
        #expect(TextMetricsKey.make(runs: [StyledRun("Hi", font: body)], options: .default, width: 150) == "style:body|150.0|Hi")
        #expect(TextMetricsKey.make(runs: [StyledRun("Hi", font: body)], options: TextLayoutOptions(lineLimit: 2, lineSpacing: 4), width: 150) == "style:body|150.0;l2;s4.0|Hi")
        #expect(TextMetricsKey.make(runs: [StyledRun("Hi", font: body)], options: TextLayoutOptions(lineLimit: 1, truncationMode: .head), width: nil) == "style:body|;l1;thead|Hi")
        #expect(TextMetricsKey.make(runs: [StyledRun("Hi", font: body)], options: TextLayoutOptions(lineLimit: 2, reservesSpace: true), width: nil) == "style:body|;l2;r|Hi")
        // Runs in the same font merge (colour boundaries do not matter); different fonts make a rich key.
        #expect(TextMetricsKey.make(runs: [StyledRun("Hel", font: body), StyledRun("lo", font: body)], options: .default, width: nil) == "style:body||Hello")
        #expect(TextMetricsKey.make(runs: [StyledRun("Big ", font: large), StyledRun("small", font: small)], options: .default, width: nil)
                == "rich:style:largeTitle=4,system:13:400:default=5||Big small")
    }

    @Test func concatenationResolvesPartModifiers() {
        let text = (Text("a").bold() + Text("b").foregroundColor(.red) + (Text("c") + Text("d").italic()).font(.title)).font(.body)
        let parts = text.parts()
        #expect(parts.map(\.string) == ["a", "b", "c", "d"])
        #expect(parts[0].modifiers.bold && parts[0].modifiers.font == .body)
        #expect(parts[1].modifiers.foregroundColor == .red && !parts[1].modifiers.bold)
        #expect(parts[2].modifiers.font == .title && parts[3].modifiers.font == .title && parts[3].modifiers.italic)
    }

    @Test @MainActor func environmentModifiersReachTheNode() {
        let runtime = Runtime()
        runtime.mount(Text("x").lineLimit(2).multilineTextAlignment(.center).truncationMode(.middle).lineSpacing(3))
        runtime.layout(in: CGSize(width: 100, height: 100))
        var node: ViewNode? = runtime.root
        while let n = node, !(n is TextNode) { node = n.structuralChildren.first }
        let text = try! #require(node as? TextNode)
        #expect(text.environment.textLayoutOptions == TextLayoutOptions(lineLimit: 2, truncationMode: .middle, lineSpacing: 3))
        #expect(text.environment.multilineTextAlignment == .center)
        let runtime2 = Runtime()
        runtime2.mount(Text("x").lineLimit(2, reservesSpace: true))
        runtime2.layout(in: CGSize(width: 100, height: 100))
        node = runtime2.root
        while let n = node, !(n is TextNode) { node = n.structuralChildren.first }
        #expect((node as? TextNode)?.environment.textLayoutOptions.reservesSpace == true)
    }
}
