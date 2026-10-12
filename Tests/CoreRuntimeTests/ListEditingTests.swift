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
    /// Lets a swiped row ease to rest (the settle takes a quarter second).
    private func settle(_ r: Runtime) {
        for _ in 0..<4 { r.advanceAnimations(elapsed: 0.1); relayout(r) }
    }

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

    struct Sectioned: View {
        let model: Model
        var body: some View {
            List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                Section("Fruit") {
                    ForEach(model.items, id: \.self) { item in Text(item)._probe(item) }
                        .onDelete { model.deleted = Array($0) }
                        .onMove { model.moved = ($0, $1) }
                }
                Section("More") {
                    ForEach(["Date", "Elderberry"], id: \.self) { item in Text(item)._probe(item) }
                        .onDelete { model.deleted = Array($0).map { $0 + 100 } }
                }
            }
        }
    }

    /// Editing across sections: each `ForEach` gets its own offsets; a row dragged past the
    /// section's end lands at the end of its own `ForEach`, never in the other.
    @Test func editingAcrossSections() {
        let model = Model()
        let r = runtime(Sectioned(model: model))
        let list = r.semanticsTree().first { $0.role == .list }!
        r.focus(semanticsIdentifier: list.identifier)
        model.selection = "Elderberry"
        relayout(r)
        #expect(r.keyDown(KeyEvent(key: .delete)))
        #expect(model.deleted == [101])
        let apple = r.probeFrames["Apple"]!, elderberry = r.probeFrames["Elderberry"]!
        r.pointerDown(at: CGPoint(x: 100, y: apple.midY))
        r.pointerMoved(to: CGPoint(x: 100, y: apple.midY + 5))
        r.pointerMoved(to: CGPoint(x: 100, y: elderberry.midY))
        r.pointerUp(at: CGPoint(x: 100, y: elderberry.midY))
        #expect(model.moved?.0 == IndexSet(integer: 0) && model.moved?.1 == 3)
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
        // A press on the delete circle reveals the row's Delete: the content slides left by the
        // cell's width and the minus turns into a bar; nothing is deleted yet.
        r.pointerDown(at: CGPoint(x: fixed.minX + 12, y: apple.midY)); r.pointerUp(at: CGPoint(x: fixed.minX + 12, y: apple.midY))
        relayout(r)
        settle(r)
        #expect(model.deleted.isEmpty)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX - 74)
        let painted = r.render(scale: 2).commands.map(\.description)
        #expect(painted.contains { $0.hasPrefix("fillRect(") && $0.contains(", 2, 10.5)") && $0.contains("#FFFFFF") }, "the bar is the minus turned upright")
        // The Delete button deletes the row.
        r.pointerDown(at: CGPoint(x: 304 - 37, y: apple.midY)); r.pointerUp(at: CGPoint(x: 304 - 37, y: apple.midY))
        #expect(model.deleted == [0])
        // A press elsewhere shuts a revealed row.
        model.deleted = []
        r.pointerDown(at: CGPoint(x: fixed.minX + 12, y: apple.midY)); r.pointerUp(at: CGPoint(x: fixed.minX + 12, y: apple.midY))
        relayout(r); settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX - 74)
        r.pointerDown(at: CGPoint(x: 150, y: fixed.midY)); r.pointerUp(at: CGPoint(x: 150, y: fixed.midY))
        settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX && model.deleted.isEmpty)
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
        // A short swipe past half the strip leaves it open, the content easing to its width.
        drag(r, from: CGPoint(x: 250, y: apple.midY), to: CGPoint(x: 150, y: apple.midY))
        let easing = r.probeFrames["Apple"]!
        #expect(easing.minX < apple.minX && easing.minX > apple.minX - 148, "the row is still easing: \(easing.minX)")
        settle(r)
        let shifted = r.probeFrames["Apple"]!
        #expect(shifted.minX < apple.minX)
        // Two 74 pt cells fill the strip up to the card's edge (304); the first declared action,
        // Trash, is the outermost, so Flag is the inner cell (probe frames are not republished
        // after the cells are placed in reverse, so the geometry is asserted directly).
        #expect(shifted.minX == apple.minX - 148)
        r.pointerDown(at: CGPoint(x: 304 - 148 + 37, y: apple.midY), type: .touch, time: 1); r.pointerUp(at: CGPoint(x: 304 - 148 + 37, y: apple.midY), time: 1.05)
        relayout(r)
        #expect(model.flagged == ["Apple"] && model.trashed.isEmpty)
        // Pressing closed the row (once it eased shut).
        settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX)
    }

    /// macOS: a trackpad's sideways scroll over a row with actions opens its strip past 30 pt
    /// and shuts it the other way; the row content eases.
    @Test func trackpadScrollSwipesOnMacOS() {
        let model = SwipeModel()
        let r = runtime(Swipeable(model: model))
        let apple = r.probeFrames["Apple"]!
        r.scrollWheel(by: CGSize(width: -20, height: 0), at: CGPoint(x: 150, y: apple.midY))
        relayout(r); settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX, "under the threshold")
        r.scrollWheel(by: CGSize(width: -20, height: 0), at: CGPoint(x: 150, y: apple.midY))
        relayout(r); settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX - 148)
        // A press on the Flag cell runs it and shuts the row.
        r.pointerDown(at: CGPoint(x: 304 - 148 + 37, y: apple.midY)); r.pointerUp(at: CGPoint(x: 304 - 148 + 37, y: apple.midY))
        relayout(r); settle(r)
        #expect(model.flagged == ["Apple"] && r.probeFrames["Apple"]!.minX == apple.minX)
        // Open again, then a scroll the other way shuts it.
        r.scrollWheel(by: CGSize(width: -40, height: 0), at: CGPoint(x: 150, y: apple.midY))
        relayout(r); settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX - 148)
        r.scrollWheel(by: CGSize(width: 40, height: 0), at: CGPoint(x: 150, y: apple.midY))
        relayout(r); settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX)
        // A vertical wheel is not a swipe.
        r.scrollWheel(by: CGSize(width: 0, height: 40), at: CGPoint(x: 150, y: apple.midY))
        relayout(r); settle(r)
        #expect(r.probeFrames["Apple"]!.minX == apple.minX)
    }

    /// A row being reordered is painted last, lifted under a shadow at its drag offset, and
    /// the rows it passes shift into its gap.
    @Test func reorderingLiftsTheRow() {
        let model = Model()
        let r = runtime(Editable(model: model))
        let apple = r.probeFrames["Apple"]!, banana = r.probeFrames["Banana"]!
        r.pointerDown(at: CGPoint(x: 100, y: apple.midY))
        r.pointerMoved(to: CGPoint(x: 100, y: apple.midY + 5))
        r.pointerMoved(to: CGPoint(x: 100, y: banana.midY + 4))
        let painted = r.render(scale: 2).commands.map(\.description)
        let shadow = painted.firstIndex { $0.hasPrefix("beginShadow") }
        #expect(shadow != nil, "the lifted row casts a shadow")
        #expect(painted.contains { $0.hasPrefix("concat(") }, "it is scaled and moved with the drag")
        // The lifted row paints after the others: its text comes last.
        let appleText = painted.lastIndex { $0.hasPrefix("drawText(\"Apple\"") }, bananaText = painted.lastIndex { $0.hasPrefix("drawText(\"Banana\"") }
        #expect(appleText != nil && bananaText != nil && appleText! > bananaText!)
        r.pointerUp(at: CGPoint(x: 100, y: banana.midY + 4))
        #expect(model.moved?.0 == IndexSet(integer: 0) && model.moved?.1 == 2)
        #expect(!r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("beginShadow") })
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
        // A pull of 200 pt past the top moves the content through the rubber band (80 in a
        // 300 pt view), past the 60 pt threshold.
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
