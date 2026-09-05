// copyable / cuttable / pasteDestination / PasteButton: ⌘C and ⌘X around the focused view put
// values on the runtime's pasteboard, ⌘V hands them to the focused destination, PasteButton
// enables when a matching value is there.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PasteboardTests {
    final class Log { var pasted: [String] = []; var cut = 0; var button: [String] = []; var written: [String] = [] }

    struct Board: View {
        let log: Log
        var body: some View {
            VStack(spacing: 20) {
                Color.red.frame(width: 60, height: 30).copyable(["hello"]).focusable()._probe("source")
                Color.orange.frame(width: 60, height: 30).cuttable(for: String.self) { log.cut += 1; return ["snip"] }.focusable()._probe("cutter")
                Color.blue.frame(width: 60, height: 30).pasteDestination(for: String.self) { log.pasted += $0 }.focusable()._probe("target")
                PasteButton(payloadType: String.self) { log.button += $0 }._probe("button")
            }
        }
    }

    private func runtime(_ log: Log) -> Runtime {
        let runtime = Runtime()
        let font = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        var entries: [String: RecordedTextEngine.Entry] = [:]
        entries[RecordedTextEngine.key(font: font, width: nil, string: "Paste")] = .init(width: 34, height: 16, firstBaseline: 13, lastBaseline: 13)
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.clipboardWriter = { log.written.append($0) }
        runtime.mount(Board(log: log))
        runtime.layout(in: CGSize(width: 300, height: 300))
        return runtime
    }

    private func click(_ r: Runtime, _ frame: CGRect) {
        r.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        r.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        r.layout(in: CGSize(width: 300, height: 300))
    }

    private func key(_ r: Runtime, _ letter: String) -> Bool {
        r.keyDown(KeyEvent(key: KeyEquivalent(Character(letter)), characters: letter, modifiers: [.command], isRepeat: false))
    }

    @Test func copyAndPasteThroughFocus() {
        let log = Log()
        let r = runtime(log)
        // Nothing focused: the shortcuts fall through.
        #expect(!key(r, "c") && !key(r, "v"))
        click(r, r.probeFrames["source"]!)
        #expect(key(r, "c"))
        #expect(r.pasteboardText == "hello" && log.written == ["hello"])
        // Paste goes to the focused destination only.
        #expect(!key(r, "v"))
        click(r, r.probeFrames["target"]!)
        #expect(key(r, "v"))
        #expect(log.pasted == ["hello"])
        // Cut replaces the pasteboard and runs the action.
        click(r, r.probeFrames["cutter"]!)
        #expect(key(r, "x") && log.cut == 1 && r.pasteboardText == "snip")
    }

    @Test func pasteButtonFollowsThePasteboard() {
        let log = Log()
        let r = runtime(log)
        let button = r.probeFrames["button"]!
        click(r, button)
        #expect(log.button.isEmpty)                       // disabled while empty
        r.setPasteboard([_TransferItem("clip")])
        r.layout(in: CGSize(width: 300, height: 300))
        click(r, r.probeFrames["button"]!)
        #expect(log.button == ["clip"])
    }
}
#endif
