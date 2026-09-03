// Accessibility (Phase 3): the semantics tree exposes text, images, headings, controls with
// their roles and values, honours hidden and combined elements, and adjusts sliders and steppers.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct SemanticsTests {
    @Observable final class Model: @unchecked Sendable { var value = 0.25; var count = 2 }

    struct Page: View {
        let model: Model
        var body: some View {
            VStack {
                Text("Heading").accessibilityAddTraits(.isHeader)
                Text("Plain")
                Image("icon").accessibilityLabel("Icon image")
                Text("Secret").accessibilityHidden(true)
                HStack { Text("Card"); Text("Detail") }.accessibilityElement(children: .combine).accessibilityLabel("Card with detail")
                Button("Save") {}.accessibilityHint("Saves").accessibilityIdentifier("save")
                Toggle("Flag", isOn: .constant(true)).toggleStyle(.switch)
                Slider(value: Binding(get: { model.value }, set: { model.value = $0 })).accessibilityLabel("Volume")
                Stepper("Count", value: Binding(get: { model.count }, set: { model.count = $0 }))
                List { Text("Row") }
            }
        }
    }

    @Test func treeRolesAndAttributes() {
        let model = Model()
        let r = Runtime()
        r.mount(Page(model: model))
        r.layout(in: CGSize(width: 320, height: 400))
        let tree = r.semanticsTree()
        let pairs = tree.map { "\($0.role.rawValue):\($0.label)" }
        #expect(pairs.contains("heading:Heading") && pairs.contains("text:Plain") && pairs.contains("image:Icon image"))
        #expect(!pairs.contains { $0.contains("Secret") })
        #expect(pairs.contains("group:Card with detail") && !pairs.contains("text:Card"))
        let save = tree.first { $0.label == "Save" }!
        #expect(save.role == .button && save.hint == "Saves" && save.accessibilityIdentifier == "save")
        let flag = tree.first { $0.label == "Flag" }!
        #expect(flag.role == .switch && flag.isOn == true)
        let slider = tree.first { $0.label == "Volume" }!
        #expect(slider.role == .slider && slider.range?.value == 0.25 && slider.value == "25 percent" && slider.isAdjustable)
        #expect(tree.contains { $0.role == .stepper })
        // A list exposes its rows.
        #expect(pairs.contains("text:Row"))
        // Steppers and sliders adjust through the tree.
        let stepper = tree.first { $0.role == .stepper }!
        r.adjust(semanticsIdentifier: stepper.identifier, increment: true)
        #expect(model.count == 3)
        r.adjust(semanticsIdentifier: slider.identifier, increment: false)
        #expect(abs(model.value - 0.15) < 1e-9)
        r.setValue(semanticsIdentifier: slider.identifier, value: 0.9)
        #expect(model.value == 0.9)
    }
}
#endif
