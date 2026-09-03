// FocusState (Phase 3): a press on a field updates the state, setting the state moves the
// runtime's focus (which the host mirrors), blur clears it, and the Boolean form works.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct FocusTests {
    enum Field: Hashable { case name, email }
    @Observable final class Model: @unchecked Sendable { var log: [String] = [] }

    struct Form: View {
        let model: Model
        @FocusState private var focus: Field?
        var body: some View {
            VStack(spacing: 10) {
                TextField("Name", text: .constant("")).focused($focus, equals: .name)._probe("name")
                TextField("Email", text: .constant("")).focused($focus, equals: .email)._probe("email")
                Button("Go") { focus = .email }._probe("go")
                Button("Clear") { focus = nil }._probe("clear")
            }
            .onChange(of: focus) { model.log.append(focus.map { "\($0)" } ?? "nil") }
        }
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let r = Runtime()
        r.mount(view)
        r.layout(in: CGSize(width: 320, height: 200))
        return r
    }

    private func press(_ r: Runtime, _ id: String) {
        let f = r.probeFrames[id]!
        r.pointerDown(at: CGPoint(x: f.midX, y: f.midY)); r.pointerUp(at: CGPoint(x: f.midX, y: f.midY))
        r.layout(in: CGSize(width: 320, height: 200))
    }

    @Test func pressesButtonsAndBlurMoveFocus() {
        let model = Model()
        let r = runtime(Form(model: model))
        #expect(r.focusedTextFieldIdentifier == nil)
        press(r, "name")
        let nameID = r.focusedTextFieldIdentifier
        #expect(nameID != nil && model.log == ["name"])
        press(r, "go")
        #expect(r.focusedTextFieldIdentifier != nil && r.focusedTextFieldIdentifier != nameID && model.log.last == "email")
        // The host reports a blur of the focused input.
        r.textField(r.focusedTextFieldIdentifier!, focused: false)
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(r.focusedTextFieldIdentifier == nil && model.log.last == "nil")
        // The host focusing an input (Tab) updates the state; clearing the state unfocuses.
        r.textField(nameID!, focused: true)
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(model.log.last == "name")
        press(r, "clear")
        #expect(r.focusedTextFieldIdentifier == nil && model.log.last == "nil")
    }

    struct Single: View {
        let model: Model
        @FocusState private var focused: Bool
        var body: some View {
            VStack {
                TextField("Name", text: .constant("")).focused($focused)._probe("field")
                Text(focused ? "on" : "off")
            }
            .onChange(of: focused) { model.log.append(focused ? "on" : "off") }
        }
    }

    @Test func booleanFocusState() {
        let model = Model()
        let r = runtime(Single(model: model))
        press(r, "field")
        #expect(model.log == ["on"])
        r.textField(r.focusedTextFieldIdentifier!, focused: false)
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(model.log == ["on", "off"])
    }
}
#endif
