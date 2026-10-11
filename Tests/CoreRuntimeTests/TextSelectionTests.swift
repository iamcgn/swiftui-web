// Text selection (sw-text-selection, Docs/elements/TextScale.md): a drag over selectable text
// selects characters, the highlight paints under the glyphs, ⌘C copies the selection, a press
// elsewhere clears it; a monospace engine (6 pt a character) makes the hit testing exact.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebGraphics

#if !os(WASI)
/// Every character 6 pt wide, lines 16 pt tall, wrapping at the width.
final class MonospaceTextEngine: TextEngine {
    private lazy var layouter = TextLayouter(measure: { text, _ in CGFloat(text.count) * 6 },
                                             metrics: { font in SystemFontMetricsTables.systemFontMetrics(for: font) })
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        layouter.layout(runs, options: options, width: width)
    }
    func metrics(for font: ResolvedFont) -> FontMetrics { SystemFontMetricsTables.systemFontMetrics(for: font).fontMetrics }
}

@Suite @MainActor struct TextSelectionTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let r = Runtime()
        r.textEngine = MonospaceTextEngine()
        r.mount(view)
        r.layout(in: CGSize(width: 200, height: 100))
        return r
    }

    @Test func dragSelectsCopiesAndClears() {
        let r = runtime(VStack(spacing: 0) {
            Text("Hello world").textSelection(.enabled)._probe("text")
            Text("Plain")._probe("plain")
        })
        let frame = r.probeFrames["text"]!
        #expect(frame.width == 66)
        // A drag from the third character to the ninth selects "llo wo".
        let y = frame.midY
        r.pointerDown(at: CGPoint(x: frame.minX + 12, y: y))
        r.pointerMoved(to: CGPoint(x: frame.minX + 48, y: y))
        r.pointerUp(at: CGPoint(x: frame.minX + 48, y: y))
        let text = r.textSelectionOwner
        #expect(text?.selectedText == "llo wo", "\(text?.selectedText as Any)")
        // The highlight: one rect under the selected characters, before the glyphs.
        let commands = r.render(scale: 1).commands.map(\.description)
        let highlight = commands.firstIndex { $0.hasPrefix("fillRect(\(Int(frame.minX + 12)), ") && $0.contains(", 36, ") }
        #expect(highlight != nil && highlight! < commands.firstIndex { $0.hasPrefix("drawText") }!, "\(commands)")
        // ⌘C copies the selection to the pasteboard.
        #expect(r.keyDown(KeyEvent(key: KeyEquivalent("c"), characters: "c", modifiers: [.command])))
        #expect(r.pasteboard.first?.load(as: String.self) == "llo wo")
        // A press elsewhere clears it; a plain text takes no selection.
        let plain = r.probeFrames["plain"]!
        r.pointerDown(at: CGPoint(x: plain.midX, y: plain.midY))
        r.pointerUp(at: CGPoint(x: plain.midX, y: plain.midY))
        #expect(r.textSelectionOwner == nil && text?.selectedText == nil)
        #expect(!r.render(scale: 1).commands.map(\.description).contains { $0.hasPrefix("fillRect") })
        // A drag backwards selects the same way; beyond the ends it clamps.
        r.pointerDown(at: CGPoint(x: frame.maxX - 1, y: y))
        r.pointerMoved(to: CGPoint(x: frame.minX - 20, y: y))
        r.pointerUp(at: CGPoint(x: frame.minX - 20, y: y))
        #expect(r.textSelectionOwner?.selectedText == "Hello world", "\(r.textSelectionOwner?.selectedText as Any)")
    }

    @Test func wrappedSelectionSpansLines() {
        let r = runtime(Text("one two three four").textSelection(.enabled)._probe("text").frame(width: 60))
        let frame = r.probeFrames["text"]!
        #expect(frame.height > 20)
        // From the first line's "two" to the second line's middle.
        r.pointerDown(at: CGPoint(x: frame.minX + 26, y: frame.minY + 8))
        r.pointerMoved(to: CGPoint(x: frame.minX + 14, y: frame.minY + 24))
        r.pointerUp(at: CGPoint(x: frame.minX + 14, y: frame.minY + 24))
        let selected = r.textSelectionOwner?.selectedText ?? ""
        #expect(selected == "two th", "\(selected)")
        #expect(r.textSelectionOwner!.selectionRects().count == 2)
    }
}
#endif
