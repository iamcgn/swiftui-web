// Phase 8 step 6, sw-textfield: value fields, editing callbacks, caret and selection, the
// keyboard attributes (Docs/elements/TextField.md). Wrapping is held by the textfield/vertical
// goldens (the unit runtime has no text metrics).
import Testing
import SwiftUI

@Observable
private final class Model {
    var age = 1234
    var price = 3.5
    var text = ""
    var log: [String] = []
}

private struct ValueForm: View {
    let model: Model
    var body: some View {
        VStack {
            TextField("Age", value: Binding(get: { model.age }, set: { model.age = $0 }), format: .number)._probe("age")
            TextField("Price", value: Binding(get: { model.price }, set: { model.price = $0 }), format: .currency(code: "USD"))._probe("price")
            Text("\(model.age)")._probe("echo")
        }
    }
}

private struct CallbackForm: View {
    let model: Model
    var body: some View {
        VStack {
            TextField("Name", text: Binding(get: { model.text }, set: { model.text = $0 }),
                      onEditingChanged: { model.log.append("editing \($0)") }, onCommit: { model.log.append("commit") })._probe("name")
            TextField("Other", text: .constant(""))._probe("other")
        }
    }
}

@Suite @MainActor struct TextFieldFormsTests {
    private let size = CGSize(width: 300, height: 300)

    private func press(_ runtime: Runtime, _ id: String) {
        let frame = runtime.probeFrames[id]!
        runtime.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        runtime.layout(in: size)
    }

    private func field(_ runtime: Runtime, _ id: String) -> Int {
        runtime.semanticsTree().first { $0.role == .textField && $0.frame == runtime.probeFrames[id]! }!.identifier
    }

    @Test func valueFieldsShowTheFormattedValueAndCommitOnSubmit() {
        let model = Model()
        let runtime = Runtime()
        runtime.mount(ValueForm(model: model))
        runtime.layout(in: size)
        let age = field(runtime, "age"), price = field(runtime, "price")
        let inputs = runtime.semanticsTree().compactMap(\.textInput)
        #expect(inputs.map(\.text) == ["1,234", "$3.50"])
        press(runtime, "age")
        // Typing holds the text in the field; the value changes on Return.
        runtime.textField(age, didChange: "56")
        runtime.layout(in: size)
        #expect(model.age == 1234)
        #expect(runtime.semanticsTree().compactMap(\.textInput).first?.text == "56")
        runtime.textFieldDidSubmit(age)
        runtime.layout(in: size)
        #expect(model.age == 56)
        #expect(runtime.semanticsTree().compactMap(\.textInput).first?.text == "56")
        // Text that does not parse leaves the value alone and the field shows the value again.
        runtime.textField(age, didChange: "abc")
        runtime.textFieldDidSubmit(age)
        runtime.layout(in: size)
        #expect(model.age == 56)
        #expect(runtime.semanticsTree().compactMap(\.textInput).first?.text == "56")
        // Focus leaving commits too: typing into the price and pressing the age field.
        runtime.textField(price, focused: true)
        runtime.textField(price, didChange: "12.25")
        runtime.textField(age, focused: true)
        runtime.layout(in: size)
        #expect(model.price == 12.25)
        #expect(runtime.semanticsTree().compactMap(\.textInput).last?.text == "$12.25")
    }

    @Test func editingCallbacksFollowFocusAndReturn() {
        let model = Model()
        let runtime = Runtime()
        runtime.mount(CallbackForm(model: model))
        runtime.layout(in: size)
        let name = field(runtime, "name")
        press(runtime, "name")
        #expect(model.log == ["editing true"])
        runtime.textField(name, didChange: "Ann")
        runtime.textFieldDidSubmit(name)
        #expect(model.text == "Ann" && model.log == ["editing true", "commit"])
        press(runtime, "other")
        #expect(model.log == ["editing true", "commit", "editing false"])
    }

    @Test func paintsTheCaretAndSelectionWhileFocused() {
        let model = Model()
        let runtime = Runtime()
        runtime.mount(CallbackForm(model: model))
        runtime.layout(in: size)
        let name = field(runtime, "name")
        func commands() -> [String] { runtime.render(scale: 2).commands.map(\.description) }
        #expect(!commands().contains { $0.contains("fillRect") && $0.contains(", 1, 16)") })
        press(runtime, "name")
        runtime.textField(name, didChange: "Ann")
        runtime.layout(in: size)
        // A 1 pt caret the line's height at the end of the (zero-width) text.
        let caret = commands().filter { $0.hasPrefix("fillRect") && $0.contains(", 1, 16)") }
        #expect(caret.count == 1, "\(commands())")
        runtime.textField(name, selectionStart: 0, end: 3)
        runtime.layout(in: size)
        // A range shows no caret (the highlight needs text widths, which the unit runtime has not).
        #expect(!commands().contains { $0.hasPrefix("fillRect") && $0.contains(", 1, 16)") })
        runtime.textField(name, selectionStart: 1, end: 1)
        runtime.layout(in: size)
        #expect(commands().contains { $0.hasPrefix("fillRect") && $0.contains(", 1, 16)") })
        // Blur removes the caret.
        runtime.textField(name, focused: false)
        runtime.layout(in: size)
        #expect(!commands().contains { $0.hasPrefix("fillRect") && $0.contains(", 1, 16)") })
    }

    @Test func keyboardAttributesReachTheInputInfo() {
        let runtime = Runtime()
        runtime.mount(VStack {
            TextField("Email", text: .constant("")).keyboardType(.emailAddress).textContentType(.emailAddress)
                .submitLabel(.next).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Plain", text: .constant(""))
            TextField("Notes", text: .constant(""), axis: .vertical)
        })
        runtime.layout(in: size)
        let inputs = runtime.semanticsTree().compactMap(\.textInput)
        #expect(inputs.count == 3)
        #expect(inputs[0].inputMode == "email" && inputs[0].inputType == "email" && inputs[0].autocomplete == "email")
        #expect(inputs[0].enterKeyHint == "next" && inputs[0].autocapitalize == "off" && !inputs[0].autocorrect)
        #expect(inputs[1].inputMode == nil && inputs[1].inputType == "text" && inputs[1].autocomplete == nil && inputs[1].enterKeyHint == nil && inputs[1].autocorrect)
        #expect(inputs[2].isMultiline && inputs[2].submitsOnReturn && inputs[2].paintsCaret)
    }
}
