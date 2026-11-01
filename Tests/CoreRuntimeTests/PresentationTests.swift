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
        // Presented: the sheet is a window the size of its content, centred (macOS 27,
        // presentation/mac-sheet), and the window behind it is not dimmed.
        #expect(r.hasPresentations)
        #expect(texts(r) == ["Open", "Inside", "Done"])
        let inside = r.probeFrames["inside"]!
        let panel = r.probeFrames["window.sheet"]!
        #expect(abs(inside.midX - 200) <= 0.5 && abs(panel.midY - 150) <= 0.5 && panel.minY > 100, "\(panel)")
        #expect(!r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("fillRect(0, 0, 400, 300) #000000@0.2") })
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
        // The arrow on the button's top edge (`arrowEdge: .top`): the popover sits above it, its
        // 13 pt window margin between (macOS 27, presentation/mac-popover), centred on it.
        #expect(inside.maxY + 13 == open.minY)
        #expect(abs(inside.midX - open.midX) <= 0.5)
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

    // MARK: Options (sw-presentations, 2026-09-18)

    struct AnchoredPopover: View {
        let model: Model
        let anchor: PopoverAttachmentAnchor
        var body: some View {
            VStack {
                Color.red.frame(width: 100, height: 40)._probe("source")
                    .popover(isPresented: Binding(get: { model.popover }, set: { model.popover = $0 }), attachmentAnchor: anchor, arrowEdge: .bottom) {
                        Text("Inside")._probe("inside")
                    }
            }
        }
    }

    @Test func popoverAttachesToARectOrAPoint() {
        let model = Model()
        model.popover = true
        let r = runtime(AnchoredPopover(model: model, anchor: .point(.topTrailing)))
        let source = r.probeFrames["source"]!, inside = r.probeFrames["inside"]!
        // The arrow on the source's bottom edge at its top trailing corner: the panel sits below
        // that point, the window margin between.
        #expect(abs(inside.midX - source.maxX) <= 0.5)
        #expect(inside.minY == source.minY + 13)
        let rect = runtime(AnchoredPopover(model: model, anchor: .rect(.rect(CGRect(x: 0, y: 0, width: 20, height: 10)))))
        let rectSource = rect.probeFrames["source"]!, rectInside = rect.probeFrames["inside"]!
        #expect(abs(rectInside.midX - (rectSource.minX + 10)) <= 0.5)
        #expect(rectInside.minY == rectSource.minY + 10 + 13)
    }

    struct StubbornPopover: View {
        let model: Model
        var body: some View {
            Button("Open") { model.popover = true }._probe("open")
                .popover(isPresented: Binding(get: { model.popover }, set: { model.popover = $0 })) {
                    Text("Inside")._probe("inside").interactiveDismissDisabled()
                }
        }
    }

    @Test func interactiveDismissDisabledKeepsThePresentation() {
        let model = Model()
        model.popover = true
        let r = runtime(StubbornPopover(model: model))
        #expect(r.hasPresentations)
        // A press outside is consumed but dismisses nothing; Escape neither.
        press(r, CGPoint(x: 5, y: 290))
        #expect(model.popover && r.hasPresentations)
        #expect(r.dismissTopmostPresentation())
        #expect(model.popover && r.hasPresentations)
        // Programmatic dismissal still works.
        model.popover = false
        relayout(r)
        #expect(!r.hasPresentations)
    }

    struct TallSheet: View {
        let model: Model
        var body: some View {
            Text("Title")
                .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.blue.frame(width: 100, height: 600)._probe("tall")
                        }
                    }
                    ._probe("scroll")
                }
        }
    }

    @Test func sheetIsLimitedToTheWindowSoItsScrollViewScrolls() {
        let model = Model()
        model.sheet = true
        let r = runtime(TallSheet(model: model))
        let scroll = r.probeFrames["scroll"]!
        // The sheet keeps 20 pt margins inside a 300 pt window and pads nothing itself.
        #expect(scroll.height == 260)
        #expect(scroll.minY == 20)
        #expect(r.probeFrames["tall"]!.height == 600)
    }

    struct TwoPresenters: View {
        let model: Model
        var body: some View {
            Text("Title")
                .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { Text("Inside")._probe("inside") }
                .alert("Title", isPresented: Binding(get: { model.alert }, set: { model.alert = $0 })) { Button("OK") {}._probe("ok") }
        }
    }

    @Test func oneViewPresentsASheetAndAnAlert() {
        let model = Model()
        let r = runtime(TwoPresenters(model: model))
        model.sheet = true
        relayout(r)
        model.alert = true
        relayout(r)
        // Both are up, the alert on top; dismissing the alert leaves the sheet.
        #expect(r.probeFrames["inside"] != nil && r.probeFrames["ok"] != nil)
        let ok = r.probeFrames["ok"]!
        press(r, CGPoint(x: ok.midX, y: ok.midY))
        relayout(r)
        #expect(!model.alert && model.sheet)
        #expect(r.probeFrames["ok"] == nil && r.probeFrames["inside"] != nil)
    }

    // `@Environment(\.presentationMode)` (the API before `dismiss`): false at the root, true in a
    // sheet and in a pushed destination, and its `dismiss()` closes either.
    final class Seen: @unchecked Sendable { var presented: [String: Bool] = [:] }

    struct ModeReader: View {
        let name: String
        let seen: Seen
        @Environment(\.presentationMode) private var presentationMode
        var body: some View {
            seen.presented[name] = presentationMode.wrappedValue.isPresented
            return Button("Done") { presentationMode.wrappedValue.dismiss() }._probe(name)
        }
    }

    struct ModeSheetPresenter: View {
        let model: Model
        let seen: Seen
        var body: some View {
            ModeReader(name: "root", seen: seen)
                .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 }), onDismiss: { model.dismissed += 1 }) {
                    ModeReader(name: "sheet", seen: seen)
                }
        }
    }

    @Test func presentationModeReadsAndDismissesASheet() {
        let model = Model(), seen = Seen()
        let r = runtime(ModeSheetPresenter(model: model, seen: seen))
        #expect(seen.presented["root"] == false)
        // At the root, dismissing does nothing.
        let root = r.probeFrames["root"]!
        press(r, CGPoint(x: root.midX, y: root.midY))
        #expect(!model.sheet && model.dismissed == 0)
        model.sheet = true
        relayout(r)
        #expect(r.hasPresentations && seen.presented["sheet"] == true)
        let done = r.probeFrames["sheet"]!
        press(r, CGPoint(x: done.midX, y: done.midY))
        #expect(!model.sheet && model.dismissed == 1)
        relayout(r)
        #expect(!r.hasPresentations)
    }

    @Observable final class PathBox: @unchecked Sendable { var path: [String] = [] }

    @Test func presentationModePopsAPushedDestination() {
        let box = PathBox(), seen = Seen()
        let r = runtime(NavigationStack(path: Binding(get: { box.path }, set: { box.path = $0 })) {
            ModeReader(name: "root", seen: seen)
                .navigationDestination(for: String.self) { _ in ModeReader(name: "pushed", seen: seen) }
        })
        #expect(seen.presented["root"] == false)
        box.path.append("Detail")
        relayout(r)
        #expect(seen.presented["pushed"] == true)
        let done = r.probeFrames["pushed"]!
        press(r, CGPoint(x: done.midX, y: done.midY))
        #expect(box.path.isEmpty)
    }
}
#endif
