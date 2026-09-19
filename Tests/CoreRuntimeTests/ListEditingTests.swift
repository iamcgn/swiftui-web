// List editing (Docs/elements/List.md): onDelete through the Delete key on selected rows, onMove
// through a vertical drag, the binding-backed editActions forms, EditButton and edit mode, and
// iOS's delete circle.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ListEditingTests {
    struct Item: Identifiable, Equatable { var id: String { name }; let name: String }

    @Observable final class Model: @unchecked Sendable {
        var items = ["Apple", "Banana", "Cherry"]
        var records = [Item(name: "Apple"), Item(name: "Banana"), Item(name: "Cherry")]
        var selection: String?
        var deleted: [Int] = []
        var moved: (IndexSet, Int)?
        var editMode: EditMode = .inactive
    }

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let font = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        for (word, width) in [("Apple", 35.0), ("Banana", 45.0), ("Cherry", 42.0), ("Edit", 25.0), ("Done", 33.0)] {
            for w: CGFloat? in [nil, 0, 300, 320, 280, 260, 240] {
                entries[RecordedTextEngine.key(font: font, width: w, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            }
        }
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V, iOS: Bool = false) -> Runtime {
        var environment = EnvironmentValues()
        if iOS { environment.platformProfile = .iOS }
        let runtime = Runtime(environment: environment)
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 300))
        return runtime
    }

    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 300)) }

    struct Editable: View {
        let model: Model
        var body: some View {
            List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                ForEach(model.items, id: \.self) { item in
                    Text(item)._probe(item)
                }
                .onDelete { model.deleted = Array($0) }
                .onMove { model.moved = ($0, $1) }
            }
        }
    }

    @Test func deleteKeyRemovesTheSelectedRows() {
        let model = Model()
        let r = runtime(Editable(model: model))
        let list = r.semanticsTree().first { $0.role == .list }!
        r.focus(semanticsIdentifier: list.identifier)
        model.selection = "Banana"
        relayout(r)
        #expect(r.keyDown(KeyEvent(key: .delete)))
        #expect(model.deleted == [1])
    }

    @Test func draggingARowMovesIt() {
        let model = Model()
        let r = runtime(Editable(model: model))
        let apple = r.probeFrames["Apple"]!, cherry = r.probeFrames["Cherry"]!
        r.pointerDown(at: CGPoint(x: 100, y: apple.midY))
        r.pointerMoved(to: CGPoint(x: 100, y: apple.midY + 20))
        r.pointerMoved(to: CGPoint(x: 100, y: cherry.maxY + 4))
        r.pointerUp(at: CGPoint(x: 100, y: cherry.maxY + 4))
        #expect(model.moved?.0 == IndexSet(integer: 0) && model.moved?.1 == 3)
    }

    struct Bound: View {
        let model: Model
        var body: some View {
            List(Binding(get: { model.records }, set: { model.records = $0 }), editActions: .all) { $item in
                Text(item.name)._probe(item.name)
            }
        }
    }

    @Test func editActionsBindingMovesThroughTheCollection() {
        let model = Model()
        let r = runtime(Bound(model: model))
        let apple = r.probeFrames["Apple"]!, banana = r.probeFrames["Banana"]!
        // Apple dragged below Banana lands after it.
        r.pointerDown(at: CGPoint(x: 100, y: apple.midY))
        r.pointerMoved(to: CGPoint(x: 100, y: banana.midY + 8))
        r.pointerUp(at: CGPoint(x: 100, y: banana.maxY + 2))
        #expect(model.records.map(\.name) == ["Banana", "Apple", "Cherry"])
    }

    @Test func collectionHelpersMatchTheOffsets() {
        var items = ["a", "b", "c", "d"]
        items.remove(atOffsets: IndexSet([0, 2]))
        #expect(items == ["b", "d"])
        var letters = ["a", "b", "c", "d"]
        letters.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(letters == ["b", "c", "a", "d"])
        letters.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(letters == ["d", "b", "c", "a"])
    }

    struct Toggler: View {
        let model: Model
        var body: some View {
            EditButton()._probe("button")
                .environment(\.editMode, Binding(get: { model.editMode }, set: { model.editMode = $0 }))
        }
    }

    @Test func editButtonTogglesTheMode() {
        let model = Model()
        let r = runtime(Toggler(model: model))
        let button = r.probeFrames["button"]!
        r.pointerDown(at: CGPoint(x: button.midX, y: button.midY)); r.pointerUp(at: CGPoint(x: button.midX, y: button.midY))
        #expect(model.editMode == .active)
        relayout(r)
        r.pointerDown(at: CGPoint(x: button.midX, y: button.midY)); r.pointerUp(at: CGPoint(x: button.midX, y: button.midY))
        #expect(model.editMode == .inactive)
    }

    struct Editing: View {
        let model: Model
        var body: some View {
            List {
                ForEach(model.items, id: \.self) { item in Text(item)._probe(item) }
                    .onDelete { model.deleted = Array($0) }
                    .onMove { model.moved = ($0, $1) }
                Text("Fixed")._probe("Fixed")
            }
            .environment(\.editMode, .constant(.active))
        }
    }

    @Test func iOSEditModeInsetsRowsAndDeletesOnTheCircle() {
        let model = Model()
        let r = runtime(Editing(model: model), iOS: true)
        let apple = r.probeFrames["Apple"]!, fixed = r.probeFrames["Fixed"]!
        // The editable row's content sits 40 further in than the fixed row's.
        #expect(apple.minX == fixed.minX + 40)
        // A press on the delete circle deletes the row.
        r.pointerDown(at: CGPoint(x: fixed.minX + 12, y: apple.midY)); r.pointerUp(at: CGPoint(x: fixed.minX + 12, y: apple.midY))
        #expect(model.deleted == [0])
    }

    // MARK: Swipe actions and pull to refresh (iOS)

    @Observable final class SwipeModel: @unchecked Sendable {
        var items = ["Apple", "Banana", "Cherry"]
        var flagged: [String] = []
        var trashed: [String] = []
        var deleted: [Int] = []
        var refreshed = 0
    }

    struct Swipeable: View {
        let model: SwipeModel
        var body: some View {
            List {
                ForEach(model.items, id: \.self) { item in
                    Text(item)._probe(item)
                        .swipeActions {
                            Button("Trash", role: .destructive) { model.trashed.append(item) }._probe("trash-\(item)")
                            Button("Flag") { model.flagged.append(item) }._probe("flag-\(item)")
                        }
                }
                .onDelete { model.deleted = Array($0) }
            }
        }
    }

    private func drag(_ r: Runtime, from: CGPoint, to: CGPoint) {
        r.pointerDown(at: from, type: .touch, time: 0)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        r.pointerMoved(to: mid, time: 0.05)
        r.pointerMoved(to: to, time: 0.1)
        r.pointerUp(at: to, time: 0.15)
        relayout(r)
    }

    @Test func swipeRevealsTheActionsAndAPressRunsOne() {
        let model = SwipeModel()
        let r = runtime(Swipeable(model: model), iOS: true)
        let apple = r.probeFrames["Apple"]!
        // A short swipe past half the strip leaves it open, the content shifted by its width.
        drag(r, from: CGPoint(x: 250, y: apple.midY), to: CGPoint(x: 150, y: apple.midY))
        let shifted = r.probeFrames["Apple"]!
        #expect(shifted.minX < apple.minX)
        // Two 74 pt cells fill the strip up to the card's edge (304); the first declared action,
        // Trash, is the outermost, so Flag is the inner cell (probe frames are not republished
        // after the cells are placed in reverse, so the geometry is asserted directly).
        #expect(shifted.minX == apple.minX - 148)
        r.pointerDown(at: CGPoint(x: 304 - 148 + 37, y: apple.midY), type: .touch, time: 1); r.pointerUp(at: CGPoint(x: 304 - 148 + 37, y: apple.midY), time: 1.05)
        relayout(r)
        #expect(model.flagged == ["Apple"] && model.trashed.isEmpty)
        // Pressing closed the row.
        #expect(r.probeFrames["Apple"]!.minX == apple.minX)
    }

    @Test func fullSwipeRunsTheOutermostAction() {
        let model = SwipeModel()
        let r = runtime(Swipeable(model: model), iOS: true)
        let banana = r.probeFrames["Banana"]!
        drag(r, from: CGPoint(x: 300, y: banana.midY), to: CGPoint(x: 40, y: banana.midY))
        #expect(model.trashed == ["Banana"])
        #expect(model.flagged.isEmpty)
    }

    struct Deletable: View {
        let model: SwipeModel
        var body: some View {
            List {
                ForEach(model.items, id: \.self) { item in Text(item)._probe(item) }
                    .onDelete { model.deleted = Array($0) }
            }
        }
    }

    @Test func fullSwipeOnADeletableRowDeletesIt() {
        let model = SwipeModel()
        let r = runtime(Deletable(model: model), iOS: true)
        let cherry = r.probeFrames["Cherry"]!
        drag(r, from: CGPoint(x: 300, y: cherry.midY), to: CGPoint(x: 40, y: cherry.midY))
        #expect(model.deleted == [2])
    }

    struct Refreshing: View {
        let model: SwipeModel
        var body: some View {
            ScrollView {
                VStack(spacing: 0) { Color.red.frame(width: 100, height: 500)._probe("content") }.frame(maxWidth: .infinity)
            }
            .refreshable { model.refreshed += 1 }
        }
    }

    @Test func pullPastTheThresholdRefreshes() async {
        let model = SwipeModel()
        let r = runtime(Refreshing(model: model), iOS: true)
        // A pull of 200 pt past the top counts half: 100, past the 60 pt threshold.
        r.pointerDown(at: CGPoint(x: 100, y: 40), type: .touch, time: 0)
        r.pointerMoved(to: CGPoint(x: 100, y: 60), time: 0.05)
        r.pointerMoved(to: CGPoint(x: 100, y: 240), time: 0.1)
        relayout(r)
        #expect(r.probeFrames["content"]!.minY > 0)
        r.pointerUp(at: CGPoint(x: 100, y: 240), time: 0.15)
        for _ in 0..<100 where model.refreshed == 0 { await Task.yield() }
        #expect(model.refreshed == 1)
        // A short pull does nothing.
        r.pointerDown(at: CGPoint(x: 100, y: 40), type: .touch, time: 2)
        r.pointerMoved(to: CGPoint(x: 100, y: 80), time: 2.05)
        r.pointerUp(at: CGPoint(x: 100, y: 80), time: 2.1)
        for _ in 0..<20 { await Task.yield() }
        #expect(model.refreshed == 1)
    }
}
#endif
