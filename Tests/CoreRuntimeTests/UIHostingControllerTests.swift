// UIHostingController (Sources/SwiftUIWebUIKit/UIHostingController.swift): a SwiftUI view inside
// a UIKit window. The content lays out in the controller's view, paints into the scene's display
// list, sizes to fit, takes UIKit touches as pointer input, joins the scene's semantics tree and
// updates when its model changes.
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Foundation

@Suite @MainActor struct UIHostingControllerTests {
    @Observable final class Model {
        var count = 0
    }

    struct Content: View {
        let model: Model
        var body: some View {
            VStack(spacing: 10) {
                Text("Count \(model.count)")
                Button("Tap") { model.count += 1 }
            }
            .padding(10)
        }
    }

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let body = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body)
        for word in ["Count 0", "Count 1", "Count 2", "Count 5", "Tap"] {
            entries[RecordedTextEngine.key(font: body, width: nil, string: word)] = .init(width: 50, height: 24.5, firstBaseline: 18.5, lastBaseline: 18.5)
        }
        return RecordedTextEngine(entries: entries, fonts: [body.key: .init(lineHeight: 24.5, spacingBelow: 8, spacingAbove: 8, textToText: 2)])
    }

    private func window(_ model: Model) -> (UIWindow, UIHostingController<Content>) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = engine()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let controller = UIHostingController(rootView: Content(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 300))
        return (window, controller)
    }

    private func commands() -> [String] {
        UIKitScene.shared.layout(in: CGSize(width: 300, height: 300))
        return UIKitScene.shared.render(scale: 2, background: false).commands.map(\.description)
    }

    @Test func contentFillsTheControllerViewAndPaints() {
        let model = Model()
        let (window, controller) = window(model)
        #expect(controller.view.frame == window.bounds)
        let painted = commands()
        // The hosting view's white ground, then the SwiftUI content offset by nothing (it fills the window).
        #expect(painted.contains { $0.hasPrefix("fillRect(0, 0, 300, 300)") })
        #expect(painted.contains { $0.contains("drawText(\"Count 0\"") })
        #expect(painted.contains { $0.contains("drawText(\"Tap\"") })
    }

    @Test func sizesToFitAndUpdates() {
        let model = Model()
        let (_, controller) = window(model)
        // Two 24.5 pt lines 10 apart in 10 pt padding: 79 tall, the wider text plus padding across.
        let ideal = controller.sizeThatFits(in: UIView.layoutFittingExpandedSize)
        #expect(ideal.height == 79)
        #expect(ideal.width == 70)
        model.count = 5
        #expect(commands().contains { $0.contains("drawText(\"Count 5\"") })
    }

    @Test func touchesReachTheContentAndSemanticsJoinTheScene() {
        let model = Model()
        let (_, _) = window(model)
        let semantics = UIKitScene.shared.semanticsTree()
        let button = semantics.first { $0.role == .button && $0.label == "Tap" }
        #expect(button != nil, "\(semantics)")
        guard let button else { return }
        // The button sits under the text, centred in the window.
        #expect(button.frame.midX == 150)
        #expect(button.frame.minY > 100)
        UIKitScene.shared.pointerDown(at: CGPoint(x: button.frame.midX, y: button.frame.midY), type: .touch, time: 1)
        UIKitScene.shared.pointerUp(at: CGPoint(x: button.frame.midX, y: button.frame.midY), time: 1.1)
        #expect(model.count == 1)
        // The accessibility route through the scene reaches it too.
        UIKitScene.shared.activate(semanticsIdentifier: button.identifier)
        #expect(model.count == 2)
    }
}
#endif
