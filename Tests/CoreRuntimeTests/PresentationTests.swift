// Sheets, popovers, alerts and picker menus (Phase 2): presented over the window by the
// runtime, laid out after the main tree, painted last and hit-tested first.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PresentationTests {
    @Observable final class Model: @unchecked Sendable {
        var sheet = false
        var popover = false
        var alert = false
        var dismissed = 0
        var choice = 1
        var tapped = 0
    }

    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let system12 = ResolvedFont(family: "system", size: 12, weight: .regular, italic: false, textStyle: nil)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Open", 30.0), ("Inside", 40.0), ("Done", 33.0), ("Title", 26.5), ("OK", 17.5), ("Cancel", 42.0), ("Apple", 35.0), ("Banana", 45.0), ("✓", 9.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        entries[RecordedTextEngine.key(font: Self.system12, width: nil, string: "✓")] = .init(width: 9, height: 15, firstBaseline: 12, lastBaseline: 12)
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 400, height: 300))
        return runtime
    }

    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 400, height: 300)) }
    private func texts(_ r: Runtime) -> [String] {
        r.render(scale: 2).commands.map(\.description).compactMap { c in c.hasPrefix("drawText(\"") ? String(c.dropFirst(10).prefix { $0 != "\"" }) : nil }
    }
    private func press(_ r: Runtime, _ p: CGPoint) { r.pointerDown(at: p); r.pointerUp(at: p) }

    struct SheetContent: View {
        let model: Model
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            VStack(spacing: 8) {
                Text("Inside")._probe("inside")
                Button("Done") { dismiss() }._probe("done")
            }
        }
    }

    struct Presenter: View {
        let model: Model
        var body: some View {
            VStack {
                Button("Open") { model.sheet = true }._probe("open")
            }
            .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 }), onDismiss: { model.dismissed += 1 }) {
                SheetContent(model: model)
            }
        }
    }

    @Test func sheetPresentsDismissesAndBlocksTheTree() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        #expect(!r.hasPresentations && texts(r) == ["Open"])
        press(r, CGPoint(x: 200, y: 150))
        relayout(r)
        // Presented: the panel hangs from the top, centred, 20 pt around its content; the window is dimmed.
        #expect(r.hasPresentations)
        #expect(texts(r) == ["Open", "Inside", "Done"])
        let inside = r.probeFrames["inside"]!
        #expect(inside.midX == 200 && inside.minY == 20)
        #expect(r.render(scale: 2).commands.map(\.description).contains("fillRect(0, 0, 400, 300) #000000@0.2"))
        // A press outside a modal panel reaches nothing beneath; the Done button dismisses through the environment.
        let opens = model.sheet
        press(r, CGPoint(x: 200, y: 250))
        #expect(model.sheet == opens && r.hasPresentations)
        let done = r.probeFrames["done"]!
        press(r, CGPoint(x: done.midX, y: done.midY))
        #expect(!model.sheet && model.dismissed == 1)
        relayout(r)
        #expect(!r.hasPresentations && texts(r) == ["Open"])
    }

    struct PopoverPresenter: View {
        let model: Model
        var body: some View {
            Button("Open") { model.popover = true }._probe("open")
                .popover(isPresented: Binding(get: { model.popover }, set: { model.popover = $0 }), arrowEdge: .top) {
                    Text("Inside")._probe("inside")
                }
        }
    }

    @Test func popoverAnchorsBelowAndDismissesOutside() {
        let model = Model()
        let r = runtime(PopoverPresenter(model: model))
        model.popover = true
        relayout(r)
        let open = r.probeFrames["open"]!, inside = r.probeFrames["inside"]!
        // Below the button (10 pt arrow) and centred on it, with 20 pt of padding.
        #expect(inside.minY == open.maxY + 10 + 20)
        #expect(abs(inside.midX - open.midX) < 0.5)
        // Not modal: a press outside dismisses (and is consumed), the binding turns false.
        press(r, CGPoint(x: 20, y: 20))
        #expect(!model.popover)
        relayout(r)
        #expect(!r.hasPresentations)
    }

    struct AlertPresenter: View {
        let model: Model
        var body: some View {
            Text("Title")
                .alert("Title", isPresented: Binding(get: { model.alert }, set: { model.alert = $0 })) {
                    Button("OK") { model.tapped += 1 }._probe("ok")
                    Button("Cancel") {}
                }
        }
    }

    @Test func alertButtonsDismiss() {
        let model = Model()
        let r = runtime(AlertPresenter(model: model))
        model.alert = true
        relayout(r)
        #expect(r.hasPresentations && texts(r).contains("Cancel"))
        let ok = r.probeFrames["ok"]!
        press(r, CGPoint(x: ok.midX, y: ok.midY))
        #expect(model.tapped == 1 && !model.alert)
        relayout(r)
        #expect(!r.hasPresentations)
    }

    struct MenuPicker: View {
        let model: Model
        var body: some View {
            Picker("Fruit", selection: Binding(get: { model.choice }, set: { model.choice = $0 })) {
                Text("Apple").tag(1); Text("Banana").tag(2)
            }
            .labelsHidden()._probe("picker")
        }
    }

    @Test func popUpPickerOpensAMenuAndSelects() {
        let model = Model()
        let r = runtime(MenuPicker(model: model))
        let picker = r.probeFrames["picker"]!
        press(r, CGPoint(x: picker.midX, y: picker.midY))
        relayout(r)
        #expect(r.hasPresentations)
        let painted = texts(r)
        #expect(painted == ["Apple", "✓", "Apple", "Banana"])   // the pop-up, then the rows (the unchecked mark is invisible)
        // The second row selects Banana and closes the menu.
        press(r, CGPoint(x: picker.minX + 40, y: picker.maxY + 2 + 4 + 22 + 11))
        #expect(model.choice == 2)
        relayout(r)
        #expect(!r.hasPresentations && texts(r) == ["Banana"])
    }
}
#endif
