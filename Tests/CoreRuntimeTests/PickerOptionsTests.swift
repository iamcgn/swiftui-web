// Phase 8 step 6, sw-picker: sources pickers, optional tags, image options, dividers and
// sections in the pop-up's menu, the focus ring (Docs/elements/Picker.md).
import Testing
import SwiftUI

@Observable
private final class Sources {
    var a = 1
    var b = 1
    var size: Int? = 2
}

private struct Item {
    var value: Binding<Int>
}

@Suite @MainActor struct PickerOptionsTests {
    private let size = CGSize(width: 360, height: 300)

    private func node(_ runtime: Runtime) -> PickerNode {
        runtime.root.descendants(where: { $0 is PickerNode }).first as! PickerNode
    }

    @Test func sourcesPickerSharesOrMixesItsSelection() {
        let model = Sources()
        let runtime = Runtime()
        let items = [Item(value: Binding(get: { model.a }, set: { model.a = $0 })), Item(value: Binding(get: { model.b }, set: { model.b = $0 }))]
        runtime.mount(Picker("Shared", sources: items, selection: \Item.value) { Text("One").tag(1); Text("Two").tag(2) }._probe("picker"))
        runtime.layout(in: size)
        let picker = node(runtime)
        #expect(picker.options.map(\.title) == ["One", "Two"])
        #expect(picker.view.selected == AnyHashable(1))
        // A choice writes to every source.
        picker.view.select.select(AnyHashable(2))
        #expect(model.a == 2 && model.b == 2)
        // Sources that disagree select nothing.
        model.b = 1
        runtime.layout(in: size)
        #expect(node(runtime).view.selected != AnyHashable(1) && node(runtime).view.selected != AnyHashable(2))
    }

    @Test func optionalTagsMatchAnOptionalSelection() {
        let model = Sources()
        let runtime = Runtime()
        runtime.mount(Picker("Size", selection: Binding(get: { model.size }, set: { model.size = $0 })) {
            Text("Small").tag(1, includeOptional: true)
            Text("Large").tag(2, includeOptional: true)
        }.pickerStyle(.segmented)._probe("picker"))
        runtime.layout(in: size)
        let picker = node(runtime)
        #expect(picker.options.map { $0.tag == picker.view.selected } == [false, true])
        picker.view.select.select(picker.options[0].tag!)
        #expect(model.size == 1)
    }

    @Test func popUpMenuCarriesDividersSectionsAndImages() {
        let runtime = Runtime()
        runtime.mount(Picker("Fruit", selection: .constant(2)) {
            Section("Fresh") {
                Label("Apple", systemImage: "leaf").tag(1)
                Label("Banana", systemImage: "moon").tag(2)
            }
            Divider()
            Text("Cherry").tag(3)
        }._probe("picker"))
        runtime.layout(in: size)
        let picker = node(runtime)
        #expect(picker.menuEntries == [.header("Fresh"), .option(title: "Apple", index: 0), .option(title: "Banana", index: 1), .divider, .option(title: "Cherry", index: 2)])
        // Options with an image show themselves; a text its title.
        #expect(picker.options[0].shown === picker.options[0].node && picker.options[2].shown !== picker.options[2].node)
        // Opening the pop-up lists the rows with the separator and the header around them.
        let frame = runtime.probeFrames["picker"]!
        runtime.pointerDown(at: CGPoint(x: frame.maxX - 10, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.maxX - 10, y: frame.midY))
        runtime.layout(in: size)
        let menu = runtime.presentations.last!
        #expect(menu.interactiveNodes.map { $0.semantics.label.split(separator: " ").last.map(String.init) } == ["Apple", "Banana", "Cherry"])
        #expect(!menu.descendants(where: { $0 is DividerNode }).isEmpty)
        #expect(menu.descendants(where: { ($0 as? TextNode)?.view.resolvedString == "Fresh" }).first != nil)
    }

    @Test(arguments: [false, true])
    func focusedControlShowsAnAccentRing(radio: Bool) {
        let runtime = Runtime()
        let picker = Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }
        runtime.mount(radio ? AnyView(picker.pickerStyle(.radioGroup)) : AnyView(picker.pickerStyle(.segmented)))
        runtime.layout(in: size)
        let before = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("strokePath") }.count
        #expect(runtime.moveFocus(forward: true))
        let after = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("strokePath") }.count
        #expect(after == before + 1)
    }
}
