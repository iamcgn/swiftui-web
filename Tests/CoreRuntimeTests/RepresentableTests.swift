// UIViewRepresentable / UIViewControllerRepresentable (decision 0014, Phase 2): a UIKit view
// tree hosted as a SwiftUI leaf. Sizing from the view's intrinsic size and priorities or the
// representable's own rule, painting at the node's position, presses turned into touches,
// bindings flowing both ways through the coordinator, the semantics tree, text input and focus
// through the host's callbacks, appearance callbacks, and dismantling.
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Foundation

@Suite @MainActor struct RepresentableTests {
    /// Counters the tests read, outside observation: an update that wrote an observed property
    /// would invalidate itself (SwiftUI forbids state writes during an update too).
    final class Counts {
        var updates = 0
        var dismantled = 0
        var appearances: [String] = []
    }

    @Observable final class Model {
        var isOn = false
        var text = "Hello"
        var showsLabel = true
        @ObservationIgnored let counts = Counts()
        var updates: Int { counts.updates }
        var dismantled: Int { counts.dismantled }
        var appearances: [String] { counts.appearances }
    }

    /// A label: an intrinsic size on both axes.
    struct LabelView: UIViewRepresentable {
        let text: String
        let model: Model
        func makeUIView(context: Context) -> UILabel {
            let label = UILabel()
            label.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .vertical)
            return label
        }
        func updateUIView(_ uiView: UILabel, context: Context) {
            uiView.text = text
            model.counts.updates += 1
        }
        static func dismantleUIView(_ uiView: UILabel, coordinator: Void) {}
    }

    /// A plain view without an intrinsic size.
    struct PlainView: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
            return view
        }
        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    /// A view that sizes itself.
    struct SizedView: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ uiView: UIView, context: Context) {}
        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
            CGSize(width: 44, height: 22)
        }
    }

    /// A switch bound to the model through its coordinator.
    struct SwitchView: UIViewRepresentable {
        @Bindable var model: Model

        final class Coordinator {
            var isOn: Binding<Bool>
            init(isOn: Binding<Bool>) { self.isOn = isOn }
        }

        func makeCoordinator() -> Coordinator { Coordinator(isOn: $model.isOn) }

        func makeUIView(context: Context) -> UISwitch {
            let toggle = UISwitch()
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            toggle.setContentHuggingPriority(.required, for: .vertical)
            let coordinator = context.coordinator
            toggle.addAction(UIAction { action in
                guard let toggle = action.sender as? UISwitch else { return }
                coordinator.isOn.wrappedValue = toggle.isOn
            }, for: .valueChanged)
            return toggle
        }

        func updateUIView(_ uiView: UISwitch, context: Context) {
            uiView.isOn = model.isOn
            context.coordinator.isOn = $model.isOn
            model.counts.updates += 1
        }
    }

    /// A text field bound to the model.
    struct FieldView: UIViewRepresentable {
        @Bindable var model: Model
        func makeUIView(context: Context) -> UITextField {
            let field = UITextField()
            field.borderStyle = .roundedRect
            field.setContentHuggingPriority(.required, for: .vertical)
            field.addAction(UIAction { action in
                if let field = action.sender as? UITextField { model.text = field.text ?? "" }
            }, for: .editingChanged)
            return field
        }
        func updateUIView(_ uiView: UITextField, context: Context) { uiView.text = model.text }
    }

    struct Dismantling: UIViewRepresentable {
        let model: Model
        final class Coordinator { let model: Model; init(_ model: Model) { self.model = model } }
        func makeCoordinator() -> Coordinator { Coordinator(model) }
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ uiView: UIView, context: Context) {}
        static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.model.counts.dismantled += 1 }
    }

    final class LoggingController: UIViewController {
        let model: Model
        init(_ model: Model) { self.model = model; super.init(nibName: nil, bundle: nil) }
        override func viewDidLoad() { super.viewDidLoad(); model.counts.appearances.append("load") }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); model.counts.appearances.append("willAppear") }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); model.counts.appearances.append("didAppear") }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); model.counts.appearances.append("willDisappear") }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); model.counts.appearances.append("layout \(Int(view.bounds.width))x\(Int(view.bounds.height))") }
    }

    struct ControllerView: UIViewControllerRepresentable {
        let model: Model
        func makeUIViewController(context: Context) -> LoggingController { LoggingController(model) }
        func updateUIViewController(_ uiViewController: LoggingController, context: Context) {}
    }

    struct Screen: View {
        let model: Model
        var body: some View {
            VStack(spacing: 0) {
                if model.showsLabel {
                    LabelView(text: model.text, model: model)._probe("label")
                }
                PlainView().frame(width: 120, height: 40)._probe("plain")
                SizedView()._probe("sized")
                SwitchView(model: model)._probe("switch")
                FieldView(model: model).frame(width: 150)._probe("field")
                Dismantling(model: model).frame(width: 10, height: 10)._probe("dismantling")
                ControllerView(model: model).frame(width: 100, height: 30)._probe("controller")
            }
            .padding(10)
        }
    }

    private static let size = CGSize(width: 300, height: 400)

    private func runtime(_ model: Model) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let font = UIFont.systemFont(ofSize: 17).resolved
        for (word, width) in [("Hello", 41.5), ("Hello!", 46), ("Longer text", 90)] {
            for options in [TextLayoutOptions.default, TextLayoutOptions(lineLimit: 1)] {
                entries[TextMetricsKey.make(runs: [StyledRun(word, font: font)], options: options, width: nil)] =
                    .init(width: width, height: 20.5, firstBaseline: 16, lastBaseline: 16)
            }
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(Screen(model: model))
        runtime.layout(in: Self.size)
        return runtime
    }

    @Test func sizesFollowIntrinsicSizePrioritiesAndOverrides() {
        let model = Model()
        let r = runtime(model)
        let label = r.probeFrames["label"]!
        // The label hugs its text on both axes: the recorded 41.5 rounds up to the pixel (41.5)
        // and the height is UIFont's one-line label height for 17 pt.
        #expect(label.width == 41.5)
        #expect(label.height > 19 && label.height < 22)
        let centredX: CGFloat = 10 + (280 - 41.5) / 2
        #expect(label.minX == centredX)
        // A plain view fills what its frame proposes.
        #expect(r.probeFrames["plain"]!.size == CGSize(width: 120, height: 40))
        // The representable's own rule wins.
        #expect(r.probeFrames["sized"]!.size == CGSize(width: 44, height: 22))
        // A switch hugs its content: the iOS 26 switch's 68 × 30 intrinsic size less its 2 pt
        // alignment inset on the right.
        #expect(r.probeFrames["switch"]!.size == CGSize(width: 66, height: 30))
        // A text field hugging vertically has an intrinsic height but no width: the frame's 150
        // across, 34 tall.
        #expect(r.probeFrames["field"]!.size == CGSize(width: 150, height: 34))
    }

    @Test func paintsAtTheNodesPosition() {
        let model = Model()
        let r = runtime(model)
        let plain = r.probeFrames["plain"]!
        let commands = r.render(scale: 2).commands.map(\.description)
        // The plain view's blue background is a rect at its frame.
        let blueRects = commands.filter { $0.contains("fillRect") && $0.contains("#0000FF") }
        // (frames are painted on the pixel grid: the y rounds to the half point)
        #expect(blueRects.count == 1 && blueRects[0].hasPrefix("fillRect(\(Int(plain.minX)), ") && blueRects[0].hasSuffix("120, 40) #0000FF"), "\(commands)")
        // The label's text is drawn in UIKit's 17 pt system font.
        #expect(commands.contains { $0.contains("drawText(\"Hello\"") && $0.contains("17") })
    }

    @Test func pressesBecomeTouchesAndBindingsFlowBack() {
        let model = Model()
        let r = runtime(model)
        let toggle = r.probeFrames["switch"]!
        let updates = model.updates
        r.pointerDown(at: CGPoint(x: toggle.midX, y: toggle.midY))
        r.pointerUp(at: CGPoint(x: toggle.midX, y: toggle.midY))
        #expect(model.isOn == true)
        // The change comes back through updateUIView on the next frame.
        #expect(r.needsFrame)
        r.layout(in: Self.size)
        #expect(model.updates > updates)
        // And a model change reaches the view.
        model.isOn = false
        r.layout(in: Self.size)
        let semantics = r.semanticsTree()
        let element = semantics.first { $0.role == .switch }!
        #expect(element.isOn == false)
    }

    @Test func semanticsListTheTreesElementsAtTheirFrames() {
        let model = Model()
        let r = runtime(model)
        let semantics = r.semanticsTree()
        let toggle = semantics.first { $0.role == .switch }!
        // The element's frame is the UIKit view's: the alignment rect plus the switch's inset.
        let alignment = r.probeFrames["switch"]!
        #expect(toggle.frame == CGRect(x: alignment.minX, y: alignment.minY, width: alignment.width + 2, height: alignment.height))
        #expect(toggle.identifier >= 20_000_000)
        let label = semantics.first { $0.role == .text && $0.label == "Hello" }!
        #expect(label.frame == r.probeFrames["label"]!)
        // Activation through the accessibility overlay flips the switch.
        r.activate(semanticsIdentifier: toggle.identifier)
        #expect(model.isOn == true)
        // A field element carries its text input, with the text rect in window coordinates.
        let field = semantics.first { $0.role == .textField }!
        #expect(field.textInput?.text == "Hello")
        #expect(r.probeFrames["field"]!.contains(field.textInput!.textRect))
    }

    @Test func textInputAndFocusRouteThroughTheHost() {
        let model = Model()
        let r = runtime(model)
        let field = r.semanticsTree().first { $0.role == .textField }!
        r.textField(field.identifier, didChange: "Hello!")
        #expect(model.text == "Hello!")
        // The label follows the model: a wider text, a wider label.
        r.layout(in: Self.size)
        #expect(r.probeFrames["label"]!.width == 46)
        // Focus from the host's input makes the field the first responder and the runtime's
        // focused text field.
        r.textField(field.identifier, focused: true)
        #expect(r.focusedTextFieldIdentifier == field.identifier)
        #expect(r.focusedIdentifier == field.identifier)
        // A press elsewhere moves focus away: the field resigns.
        r.focus(semanticsIdentifier: nil)
        #expect(r.focusedTextFieldIdentifier == nil)
        #expect(r.semanticsTree().first { $0.role == .textField } != nil)
        r.textField(field.identifier, focused: true)
        #expect(r.focusedTextFieldIdentifier == field.identifier)
        r.textField(field.identifier, focused: false)
        #expect(r.focusedTextFieldIdentifier == nil)
    }

    @Test func controllersGetAppearanceCallbacksAndDismantlingRuns() {
        let model = Model()
        let r = runtime(model)
        let first: [String] = Array(model.appearances.prefix(2))
        #expect(first == ["load", "willAppear"], "\(model.appearances)")
        #expect(model.appearances.contains("didAppear"))
        #expect(model.appearances.contains("layout 100x30"))
        #expect(r.probeFrames["controller"]!.size == CGSize(width: 100, height: 30))
        // Removing the label from the tree dismantles nothing else; the dismantling view goes
        // when the whole screen does.
        model.showsLabel = false
        r.layout(in: Self.size)
        #expect(r.probeFrames["label"] == nil)
        #expect(model.dismantled == 0)
        r.mount(Text("gone"))
        r.layout(in: Self.size)
        #expect(model.dismantled == 1)
        #expect(model.appearances.contains("willDisappear"))
    }
}
#endif
