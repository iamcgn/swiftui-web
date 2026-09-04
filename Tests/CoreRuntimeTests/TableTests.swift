// Table: the column width regimes (grow, shrink, overflow; fixed and flexible columns), the
// header and row painting (dividers, bands), selection by press and keys, and sorting by header
// presses. Layout against goldens is in GoldenFrameTests.
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct TableTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let bold13 = ResolvedFont(family: "system", size: 13, weight: .bold, italic: false, textStyle: nil)

    struct Fruit: Identifiable, Sendable { let id: Int; let name: String; let color: String; let count: Int }
    static let fruits = [Fruit(id: 1, name: "Apple", color: "Red", count: 3), Fruit(id: 2, name: "Banana", color: "Yellow", count: 12),
                         Fruit(id: 3, name: "Cherry", color: "Red", count: 40)]

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 360, height: 220)) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Apple", 35.0), ("Banana", 45.0), ("Cherry", 41.5), ("Red", 23.5), ("Yellow", 38.5), ("3", 8.5), ("12", 14.0), ("40", 16.5),
                              ("Name", 35.5), ("Color", 33.0), ("Count", 36.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.bold13, width: nil, string: word)] = .init(width: width + 2, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 360, height: 220)) }
    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
    private func press(_ r: Runtime, _ point: CGPoint) { r.pointerDown(at: point); r.pointerUp(at: point) }

    private func column(_ width: _TableColumnWidth = .automatic, sortable: Bool = false, index: Int = 0) -> _TableColumnDescriptor {
        _TableColumnDescriptor(title: "C", width: width, sortable: sortable, sortOrder: nil, index: index)
    }

    @Test func columnRegimes() {
        let auto = column()
        // Grow: the pitches fill the width less 15 and share the surplus, in half points.
        #expect(TableNode.columnFrames([auto, auto], width: 360).map(\.minX) == [8, 180.5])
        #expect(TableNode.columnFrames([auto, auto], width: 360).map(\.width) == [169.5, 169.5])
        #expect(TableNode.columnFrames([auto, auto, auto], width: 380).map(\.minX) == [8, 129.5, 251])
        #expect(TableNode.columnFrames([auto, auto, auto, auto], width: 600).map(\.minX) == [8, 154.5, 301, 447.5])
        // Shrink: ideals that do not fit lose 15 pt in all, while they fit the width alone.
        #expect(TableNode.columnFrames([auto, auto, auto], width: 360).map(\.minX) == [8, 120, 232])
        #expect(TableNode.columnFrames([auto, auto, auto], width: 360).map(\.width) == [109, 109, 109])
        #expect(TableNode.columnFrames([auto, auto], width: 240).map(\.minX) == [8, 117.5])
        #expect(TableNode.columnFrames([auto, auto, auto, auto], width: 480).map(\.minX) == [8, 121, 234, 347])
        // Overflow: the columns keep their 117 pt pitch.
        #expect(TableNode.columnFrames([auto, auto], width: 200).map(\.minX) == [8, 125])
        #expect(TableNode.columnFrames([auto, auto, auto], width: 350).map(\.minX) == [8, 125, 242])
        // Fixed columns are their width plus the 14 pt insets and never grow; flexible ones grow
        // to their maximum, the surplus passing to the rest.
        let fixed = column(.fixed(80)), flexible = column(.flexible(min: 40, ideal: 60, max: 100))
        #expect(TableNode.columnFrames([fixed, flexible, auto], width: 360).map(\.minX) == [8, 105, 209])
        #expect(TableNode.columnFrames([fixed, flexible, auto], width: 360).map(\.width) == [94, 101, 141])
        #expect(TableNode.columnFrames([flexible, auto], width: 360).map(\.minX) == [8, 125])
        #expect(TableNode.columnFrames([flexible, auto], width: 360).map(\.width) == [114, 225])
        #expect(TableNode.columnFrames([column(.flexible(min: 150, ideal: 200, max: nil)), auto], width: 360).map(\.minX) == [8, 230.5])
        #expect(TableNode.columnFrames([column(.flexible(min: nil, ideal: 60, max: nil)), auto], width: 360).map(\.minX) == [8, 160.5])
        #expect(TableNode.columnFrames([fixed, auto], width: 230).map(\.minX) == [8, 105])
        // Shrinking spares fixed columns and respects minimums.
        #expect(TableNode.columnFrames([flexible, auto], width: 200).map(\.minX) == [8, 77.5])
        #expect(TableNode.columnFrames([fixed, fixed], width: 200).map(\.minX) == [8, 105])
    }

    @Test func layoutAndPainting() {
        let r = runtime(Table(Self.fruits) {
            TableColumn("Name", value: \.name)
            TableColumn("Color") { Text($0.color)._probe("color\($0.id)") }
            TableColumn("Count") { Text("\($0.count)")._probe("count\($0.id)") }
        }._probe("table"))
        // The table fills its proposal; cells sit 8 pt into their columns, 4 pt into 24 pt rows from 33.
        #expect(r.probeFrames["table"] == CGRect(x: 0, y: 0, width: 360, height: 220))
        #expect(r.probeFrames["color1"] == CGRect(x: 128, y: 37, width: 23.5, height: 16))
        #expect(r.probeFrames["count3"] == CGRect(x: 240, y: 85, width: 16.5, height: 16))
        let painted = commands(r)
        // White ground, the header's bottom line at 27, dividers at the end of each 3 pt gap
        // (the last column's too: the shrunk columns leave room), alternating bands 10 pt in.
        #expect(painted.contains { $0.hasPrefix("fillRect(0, 0, 360, 220) #FFFFFF") })
        #expect(painted.contains { $0.hasPrefix("fillRect(0, 27, 360, 1) #000000") })
        for x in [119, 231, 340] {
            #expect(painted.contains { $0.hasPrefix("fillRect(\(x), 6, 1, 16) #000000") }, "divider at \(x)")
        }
        #expect(painted.contains { $0.hasPrefix("fillRRect(10, 57, 340, 24) r=6 #000000") })
        #expect(painted.contains { $0.hasPrefix("fillRRect(10, 201, 340, 24) r=6 #000000") })
        #expect(!painted.contains { $0.hasPrefix("fillRRect(10, 33, 340, 24)") })
        // Titles 10 pt into their columns; the sort-less header is regular weight.
        #expect(painted.contains { $0.hasPrefix("drawText(\"Name\"") && $0.contains(" at 18,") })
        #expect(painted.contains { $0.hasPrefix("drawText(\"Color\"") && $0.contains(" at 130,") })
        // A table without a selection is a plain group in the accessibility tree.
        #expect(r.semanticsTree().contains { $0.role == .group && $0.label == "Name, Color, Count" })
    }

    @Test func selectionByPressAndKeys() {
        let model = _TableSelectionBox()
        let r = runtime(Table(Self.fruits, selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            TableColumn("Name", value: \.name)
            TableColumn("Color", value: \.color)
        })
        let table = r.semanticsTree().first { $0.role == .list }!
        #expect(table.isFocusable)
        // A press on the second row selects it and focuses the table; the band is painted.
        press(r, CGPoint(x: 100, y: 70))
        #expect(model.selection == 2 && r.focusedIdentifier == table.identifier)
        relayout(r)
        #expect(commands(r).contains { $0.hasPrefix("fillRRect(10, 57, 340, 24) r=6 #000000") && $0.contains("@0.137") })
        // Header presses do not select; a press on the selected row toggles it off.
        press(r, CGPoint(x: 100, y: 10))
        #expect(model.selection == 2)
        press(r, CGPoint(x: 100, y: 70))
        #expect(model.selection == nil)
        // Arrow keys move the selection, Home/End jump.
        #expect(r.keyDown(KeyEvent(key: .downArrow)) && model.selection == 1)
        #expect(r.keyDown(KeyEvent(key: .downArrow)) && model.selection == 2)
        #expect(r.keyDown(KeyEvent(key: .end)) && model.selection == 3)
        #expect(r.keyDown(KeyEvent(key: .downArrow)) && model.selection == 3)
        #expect(r.keyDown(KeyEvent(key: .upArrow)) && model.selection == 2)
        #expect(r.keyDown(KeyEvent(key: .home)) && model.selection == 1)
        #expect(!r.keyDown(KeyEvent(key: .leftArrow)))

        // Shift extends a multiple selection from the anchor.
        let set = _TableSetBox()
        let m = runtime(Table(Self.fruits, selection: Binding(get: { set.selection }, set: { set.selection = $0 })) {
            TableColumn("Name", value: \.name)
        })
        press(m, CGPoint(x: 100, y: 40))
        #expect(set.selection == [1])
        #expect(m.keyDown(KeyEvent(key: .downArrow, modifiers: .shift)) && set.selection == [1, 2])
        #expect(m.keyDown(KeyEvent(key: .end, modifiers: .shift)) && set.selection == [1, 2, 3])
        #expect(m.keyDown(KeyEvent(key: .upArrow)) && set.selection == [2])
    }

    @Test func sortingByHeaderPresses() {
        let model = _TableSortBox()
        let r = runtime(_SortedFruits(model: model))
        // The sorted column's title is bold and carries the chevron; the sorted first column
        // draws a divider inside its leading edge.
        var painted = commands(r)
        #expect(painted.contains { $0.hasPrefix("drawText(\"Name\"") && $0.contains("w700") })
        #expect(painted.contains { $0.hasPrefix("strokePath") })
        #expect(painted.contains { $0.hasPrefix("fillRect(9, 6, 1, 16) #000000") })
        // Pressing another sortable header sorts by it forward; again reverses; an unsortable
        // header does nothing. The rows follow the data the app re-sorts.
        press(r, CGPoint(x: 150, y: 10))
        #expect(model.order.count == 1 && model.order.first?.keyPath == \Fruit.count && model.order.first?.order == .forward)
        relayout(r)
        #expect(r.probeFrames["count1"]?.minY == 37 && r.probeFrames["count3"]?.minY == 85)
        press(r, CGPoint(x: 150, y: 10))
        #expect(model.order.first?.order == .reverse)
        relayout(r)
        #expect(r.probeFrames["count3"]?.minY == 37 && r.probeFrames["count1"]?.minY == 85)
        painted = commands(r)
        #expect(painted.contains { $0.hasPrefix("drawText(\"Count\"") && $0.contains("w700") })
        #expect(!painted.contains { $0.hasPrefix("fillRect(9, 6, 1, 16)") })
        press(r, CGPoint(x: 300, y: 10))
        #expect(model.order.first?.keyPath == \Fruit.count && model.order.first?.order == .reverse)
    }
}

/// Sorts its rows in its body, as an app does, so the table re-sorts when the order changes.
struct _SortedFruits: View {
    let model: _TableSortBox
    var body: some View {
        Table(TableTests.fruits.sorted(using: model.order), sortOrder: Binding(get: { model.order }, set: { model.order = $0 })) {
            TableColumn("Name", value: \.name) { Text($0.name)._probe("name\($0.id)") }
            TableColumn("Count", value: \.count) { Text("\($0.count)")._probe("count\($0.id)") }
            TableColumn("Color") { Text($0.color) }
        }._probe("table")
    }
}

@Observable @MainActor final class _TableSelectionBox { var selection: Int? }
@Observable @MainActor final class _TableSetBox { var selection: Set<Int> = [] }
@Observable @MainActor final class _TableSortBox { var order = [KeyPathComparator(\TableTests.Fruit.name)] }
#endif
