// Phase 8 step 6, sw-accessibility: custom, default, escape and adjustable actions, actions
// from buttons, sort priority, heading levels, live regions, help as a description,
// accessibilityRepresentation and accessibilityChildren, accessibilityFocused, custom content,
// and rotors resolved to their entries.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor fileprivate final class Log { var events: [String] = [] }

@Suite @MainActor struct AccessibilityActionsTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 300))
        return runtime
    }

    private func element(_ r: Runtime, _ label: String) -> SemanticsNode? { r.semanticsTree().first { $0.label == label } }

    @Test func actionsOfEveryKind() {
        let log = Log()
        let r = runtime(VStack {
            Text("Card")
                .accessibilityAction { log.events.append("default") }
                .accessibilityAction(.escape) { log.events.append("escape") }
                .accessibilityAction(named: "Archive") { log.events.append("archive") }
                .accessibilityAction(action: { log.events.append("star") }, label: { Label("Star", systemImage: "star") })
            Text("Volume").accessibilityAdjustableAction { log.events.append($0 == .increment ? "up" : "down") }
            Text("Row").accessibilityActions { Button("Delete") { log.events.append("delete") }; Button("Share") { log.events.append("share") } }
        })
        let card = element(r, "Card")!
        // A default action makes the text a button to the host; the named actions are listed.
        #expect(card.role == .button && card.customActions == ["Archive", "Star"])
        r.activate(semanticsIdentifier: card.identifier)
        r.performAccessibilityAction(semanticsIdentifier: card.identifier, name: "Archive")
        r.performAccessibilityAction(semanticsIdentifier: card.identifier, name: "Star")
        r.performAccessibilityAction(semanticsIdentifier: card.identifier, name: "Missing")
        r.focus(semanticsIdentifier: card.identifier)
        #expect(r.keyDown(KeyEvent(key: .escape)))
        #expect(log.events == ["default", "archive", "star", "escape"])
        // An adjustable text is a spinbutton the host steps.
        let volume = element(r, "Volume")!
        #expect(volume.role == .stepper && volume.isAdjustable)
        r.adjust(semanticsIdentifier: volume.identifier, increment: true)
        r.adjust(semanticsIdentifier: volume.identifier, increment: false)
        #expect(log.events.suffix(2) == ["up", "down"])
        // Buttons in accessibilityActions become actions named by their titles.
        let row = element(r, "Row")!
        #expect(row.customActions == ["Delete", "Share"])
        r.performAccessibilityAction(semanticsIdentifier: row.identifier, name: "Share")
        #expect(log.events.last == "share")
    }

    @Test func orderHeadingsLiveRegionsAndDescriptions() {
        let r = runtime(VStack {
            Text("Second").accessibilitySortPriority(1)
            Text("Third")
            Text("First").accessibilitySortPriority(2)
            Text("Title").accessibilityHeading(.h1)
            Text("Section").accessibilityHeading(.h3)
            Text("Clock").accessibilityAddTraits(.updatesFrequently)
            Button("Save") {}.help("Saves the document")
            Text("Chosen").accessibilityAddTraits(.isSelected)
            Text("Photo").accessibilityCustomContent("Taken", "Yesterday").accessibilityHint("Opens")
        })
        let labels = r.semanticsTree().map(\.label)
        #expect(Array(labels.prefix(3)) == ["First", "Second", "Third"])
        #expect(element(r, "Title")?.role == .heading && element(r, "Title")?.headingLevel == 1)
        #expect(element(r, "Section")?.headingLevel == 3)
        #expect(element(r, "Clock")?.isLive == true)
        #expect(element(r, "Save")?.description == "Saves the document")
        #expect(element(r, "Chosen")?.isSelected == true)
        #expect(element(r, "Photo")?.hint == "Opens. Taken: Yesterday")
    }

    @Observable final class Model: @unchecked Sendable { var value = 0.5 }

    @Test func representationAndChildren() {
        let model = Model()
        let r = runtime(VStack {
            Color.red.frame(width: 100, height: 20)
                .accessibilityRepresentation { Slider(value: Binding(get: { model.value }, set: { model.value = $0 })).accessibilityLabel("Level") }
                ._probe("bar")
            Color.blue.frame(width: 100, height: 40)
                .accessibilityChildren { VStack { Text("Alpha"); Text("Beta") } }
                .accessibilityLabel("Pair")
        })
        let tree = r.semanticsTree()
        // The representation's slider stands in for the bar, over the bar's frame, and adjusts the binding.
        let level = tree.first { $0.label == "Level" }!
        #expect(level.role == .slider)
        // Laid out with the bar's proposal: its width and origin, its own height.
        #expect(level.frame.origin == r.probeFrames["bar"]?.origin && level.frame.width == r.probeFrames["bar"]?.width)
        r.setValue(semanticsIdentifier: level.identifier, value: 0.8)
        #expect(model.value == 0.8)
        #expect(!tree.contains { $0.role == .group && $0.label == "" && $0.frame == r.probeFrames["bar"] })
        // The children view's elements sit under a container element with the view's label.
        let labels = tree.map { "\($0.role.rawValue):\($0.label)" }
        #expect(labels.contains("group:Pair") && labels.contains("text:Alpha") && labels.contains("text:Beta"))
        #expect(labels.firstIndex(of: "group:Pair")! < labels.firstIndex(of: "text:Alpha")!)
    }

    struct Focused: View {
        @AccessibilityFocusState private var onError: Bool
        var body: some View {
            VStack {
                Text("Error").accessibilityFocused($onError)
                Button("Submit") { onError = true }
                Text(onError ? "Focused" : "Idle")
            }
        }
    }

    @Test func accessibilityFocusFollowsTheState() {
        let r = runtime(Focused())
        let error = element(r, "Error")!
        #expect(error.isFocusable)
        let submit = element(r, "Submit")!
        r.activate(semanticsIdentifier: submit.identifier)
        r.layout(in: CGSize(width: 320, height: 300))
        #expect(r.focusedIdentifier == error.identifier)
        #expect(element(r, "Focused") != nil)
        // Host focus elsewhere clears the state.
        r.focus(semanticsIdentifier: submit.identifier)
        r.layout(in: CGSize(width: 320, height: 300))
        #expect(element(r, "Idle") != nil)
    }

    struct Rotored: View {
        @Namespace private var namespace
        struct Item: Identifiable { let id: Int; let name: String }
        let items = [Item(id: 1, name: "Apple"), Item(id: 2, name: "Banana")]
        var body: some View {
            VStack {
                ForEach(items) { item in Text(item.name).accessibilityRotorEntry(id: item.id, in: namespace) }
                Text("Footer").accessibilityRotorEntry(id: "footer", in: namespace)
            }
            .accessibilityRotor("Fruit", entries: items, entryLabel: \.name)
            .accessibilityRotor(.headings) {
                AccessibilityRotorEntry("Bottom", id: "footer", in: namespace)
                AccessibilityRotorEntry("Nowhere", id: "nothing", in: namespace)
            }
        }
    }

    @Test func rotorsResolveToTheirEntries() {
        let r = runtime(Rotored())
        let tree = r.semanticsTree()
        let apple = tree.first { $0.label == "Apple" }!, banana = tree.first { $0.label == "Banana" }!, footer = tree.first { $0.label == "Footer" }!
        // The VStack has no element of its own: the rotors give it one.
        let holder = tree.first { !$0.rotors.isEmpty }!
        #expect(holder.rotors.count == 2)
        #expect(holder.rotors[0] == SemanticsRotor(label: "Fruit", entries: [.init(label: "Apple", target: apple.identifier), .init(label: "Banana", target: banana.identifier)]))
        #expect(holder.rotors[1] == SemanticsRotor(label: "Headings", entries: [.init(label: "Bottom", target: footer.identifier), .init(label: "Nowhere", target: nil)]))
    }
}
#endif
