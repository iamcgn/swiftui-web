// NSViewRepresentable / NSViewControllerRepresentable without AppKit (ix-appkit): the protocols
// compile with any object as the view, the node is sized by the representable (else the
// proposal), updates and dismantling run, and nothing is painted where the view would be.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
// No Foundation import: on wasm its CGSize would be ambiguous with WebGraphics' in the
// representable's `sizeThatFits` signatures, and nothing here needs it.

@Suite @MainActor struct NSViewRepresentableTests {
    final class Box { var updates = 0; var dismantled = 0; var text = "" }

    struct Sized: NSViewRepresentable {
        let box: Box
        let text: String
        func makeNSView(context: Context) -> Box { box }
        func updateNSView(_ nsView: Box, context: Context) { nsView.updates += 1; nsView.text = text }
        static func dismantleNSView(_ nsView: Box, coordinator: Void) { nsView.dismantled += 1 }
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: Box, context: Context) -> CGSize? { CGSize(width: 120, height: 40) }
    }

    struct Filling: NSViewRepresentable {
        func makeNSView(context: Context) -> Box { Box() }
        func updateNSView(_ nsView: Box, context: Context) {}
    }

    final class Controller { let view = Box() }
    struct Controlled: NSViewControllerRepresentable {
        func makeNSViewController(context: Context) -> Controller { Controller() }
        func updateNSViewController(_ nsViewController: Controller, context: Context) { nsViewController.view.updates += 1 }
        func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: Controller, context: Context) -> CGSize? { CGSize(width: 50, height: 50) }
    }

    @Observable final class Model { var text = "one"; var shown = true }

    struct Screen: View {
        let model: Model
        let box: Box
        var body: some View {
            VStack(spacing: 0) {
                if model.shown { Sized(box: box, text: model.text)._probe("sized") }
                Filling()._probe("filling")
                Controlled()._probe("controlled")
            }
        }
    }

    @Test func sizedUpdatedAndDismantled() {
        let model = Model(), box = Box()
        let r = Runtime()
        r.mount(Screen(model: model, box: box))
        r.layout(in: CGSize(width: 300, height: 400))
        #expect(r.probeFrames["sized"]?.size == CGSize(width: 120, height: 40))
        #expect(r.probeFrames["controlled"]?.size == CGSize(width: 50, height: 50))
        // Without a size of its own the view takes the proposal.
        #expect(r.probeFrames["filling"]?.size == CGSize(width: 300, height: 310))
        #expect(box.updates == 1 && box.text == "one")
        model.text = "two"
        r.layout(in: CGSize(width: 300, height: 400))
        #expect(box.updates == 2 && box.text == "two")
        // Nothing is painted where the view sits: the display list has no command inside its frame.
        let frame = r.probeFrames["sized"]!
        let inside = r.render(scale: 2).commands.map(\.description).filter { $0.contains("fillRect(\(Int(frame.minX))") || $0.contains("drawText") }
        #expect(inside.isEmpty, "\(inside)")
        model.shown = false
        r.layout(in: CGSize(width: 300, height: 400))
        #expect(box.dismantled == 1 && r.probeFrames["sized"] == nil)
    }
}
