// A UIKit drag inside a representable (uk-dragdrop): the hosted tree's `UIDragInteraction`
// lifts under the runtime's pointer, the runtime paints the tree's preview and carries the
// session across the app boundary through its own external entry points.
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import UIKit
import WebGraphics
import Foundation

@Suite @MainActor struct HostedDragDropTests {
    @MainActor final class Model: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
        let well = UIView()
        var dropped: [String] = []
        var entered = 0
        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
            let item = UIDragItem(itemProvider: NSItemProvider(object: "Hosted" as NSString))
            item._preloadText("Hosted")   // Foundation's provider loads later; the test wants it now
            return [item]
        }
        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool { session.canLoadObjects(ofClass: String.self) }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) { entered += 1 }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal { UIDropProposal(operation: .copy) }
        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
            session.loadObjects(ofClass: String.self) { [self] strings in dropped += strings }
        }
    }

    struct Board: UIViewRepresentable {
        let model: Model
        func makeUIView(context: Context) -> UIView {
            let root = UIView()
            let card = UIView(frame: CGRect(x: 10, y: 10, width: 80, height: 40))
            card.backgroundColor = .systemIndigo
            card.addInteraction(UIDragInteraction(delegate: model))
            root.addSubview(card)
            model.well.frame = CGRect(x: 10, y: 100, width: 180, height: 80)
            model.well.backgroundColor = .systemBlue
            model.well.addInteraction(UIDropInteraction(delegate: model))
            root.addSubview(model.well)
            return root
        }
        func updateUIView(_ uiView: UIView, context: Context) {}
        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? { CGSize(width: 200, height: 200) }
    }

    struct Screen: View {
        let model: Model
        var body: some View {
            VStack(spacing: 0) {
                Color.clear.frame(height: 50)
                Board(model: model)
                Spacer()
            }
        }
    }

    private func runtime(_ model: Model) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(Screen(model: model))
        runtime.layout(in: CGSize(width: 200, height: 400))
        return runtime
    }

    @Test func hostedDragLiftsPaintsAndDrops() {
        let model = Model()
        let r = runtime(model)
        // The board sits 50 down: the card at (10, 60), the well at (10, 150).
        #expect(r.hasDragSource(at: CGPoint(x: 50, y: 80)) && !r.hasDragSource(at: CGPoint(x: 150, y: 80)))
        r.pointerDown(at: CGPoint(x: 50, y: 80), type: .mouse, time: 0)
        r.pointerMoved(to: CGPoint(x: 56, y: 80), time: 0.05)
        #expect(r.isDragging)
        r.pointerMoved(to: CGPoint(x: 100, y: 190), time: 0.1)
        #expect(model.entered == 1)
        // The preview rides with the pointer: the card's indigo painted inside an 0.8 group at
        // the grab offset (40 left, 20 up of the pointer).
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("beginGroup") && $0.contains("0.8") }, "\(commands)")
        #expect(commands.contains { $0.hasPrefix("fillRect(60, 170, 80, 40)") }, "\(commands)")
        r.pointerUp(at: CGPoint(x: 100, y: 190), time: 0.2)
        #expect(!r.isDragging && model.dropped == ["Hosted"])
    }

    @Test func hostedDragAcrossTheAppBoundary() {
        let model = Model()
        let r = runtime(model)
        let items = r.beginExternalDrag(at: CGPoint(x: 50, y: 80))
        #expect(items == [ExternalDragItem(type: "text/plain", text: "Hosted")] && r.isDragging)
        #expect(r.externalDragItems() == items && r.externalDragPreview()?.size == CGSize(width: 80, height: 40))
        #expect(r.externalDragUpdated(types: ["text/plain"], at: CGPoint(x: 100, y: 190)) && model.entered == 1)
        r.externalDragEnded(dropped: false)
        #expect(!r.isDragging)
        // A drag from outside lands in the hosted well when nothing of the runtime's takes it.
        #expect(r.externalDragUpdated(types: ["text/plain"], at: CGPoint(x: 100, y: 190)))
        #expect(r.externalDrop(items: [ExternalDragItem(type: "text/plain", text: "Outside")], at: CGPoint(x: 100, y: 190)))
        #expect(model.dropped == ["Outside"] && !r.isDragging)
    }
}
#endif
