// List (Phase 2): row layout with insets and the minimum height, section headers, separators,
// row backgrounds, selection through presses, styles. Layout against goldens is in
// GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ListTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    static let header = ResolvedFont(family: "system", size: 11, weight: .semibold, italic: false, textStyle: .subheadline, weightOverridden: true)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Apple", 35.0), ("Banana", 45.0), ("Cherry", 41.5)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        entries[RecordedTextEngine.key(font: Self.header, width: nil, string: "Fruits")] = .init(width: 31.5, height: 16, firstBaseline: 12, lastBaseline: 12)
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    struct Item: Identifiable, Hashable { let id: Int; let name: String }
    static let items = [Item(id: 1, name: "Apple"), Item(id: 2, name: "Banana"), Item(id: 3, name: "Cherry")]

    @Test func rowsInsetsAndSeparators() {
        let r = runtime(List {
            Text("Apple")._probe("a")
            Color.red.frame(height: 40)._probe("tall")
            Text("Banana").listRowInsets(EdgeInsets(top: 2, leading: 30, bottom: 2, trailing: 10))._probe("inset")
            Text("Cherry").listRowSeparator(.hidden)._probe("last")
        }._probe("list"))
        #expect(r.probeFrames["list"] == CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(r.probeFrames["a"] == CGRect(x: 16, y: 14, width: 35, height: 16))
        #expect(r.probeFrames["tall"] == CGRect(x: 16, y: 38, width: 288, height: 40))
        #expect(r.probeFrames["inset"] == CGRect(x: 46, y: 86, width: 45, height: 16))
        #expect(r.probeFrames["last"] == CGRect(x: 16, y: 110, width: 41.5, height: 16))
        let commands = r.render(scale: 2).commands.map(\.description)
        // Background first, then rows, then separators below the first three rows (none under the last).
        #expect(commands.first == "fillRect(0, 0, 320, 200) #FFFFFF")
        let separators = commands.filter { $0.hasPrefix("fillRect") && $0.contains("#000000@\(25.0 / 255)") }
        #expect(separators == ["fillRect(16, 33, 288, 1) #000000@\(25.0 / 255)", "fillRect(16, 81, 288, 1) #000000@\(25.0 / 255)",
                               "fillRect(46, 105, 258, 1) #000000@\(25.0 / 255)"])
    }

    @Test func sectionsStyleTheirHeaders() {
        let r = runtime(List {
            Section("Fruits") { Text("Apple")._probe("apple") }
            Section { Text("Banana")._probe("banana") }
        })
        #expect(r.probeFrames["apple"] == CGRect(x: 16, y: 42, width: 35, height: 16))
        #expect(r.probeFrames["banana"] == CGRect(x: 16, y: 86, width: 45, height: 16))
        let commands = r.render(scale: 2).commands.map(\.description)
        // The first header is drawn once, pinned at the top in the semibold subheadline, secondary
        // colour; its in-flow slot is blank and has no separator (list/sections).
        #expect(commands.filter { $0.contains("\"Fruits\"") }.count == 1)
        #expect(commands.contains { $0.hasPrefix("drawText(\"Fruits\" system 11 w600 at 16,17.5 #000000@0.5") })
        #expect(!commands.contains { $0.hasPrefix("fillRect(16, 37") })
        // Rows keep their separators, including the last row of a section.
        #expect(commands.contains { $0.hasPrefix("fillRect(16, 61, 288, 1)") })
    }

    @Test func rowBackgroundsAndStyles() {
        let r = runtime(List { Text("Apple").listRowBackground(Color.yellow)._probe("a"); Text("Banana")._probe("b") })
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains("fillRect(0, 10, 320, 24) #FFCC00"))
        let plain = runtime(List { Text("Apple")._probe("a") }.listStyle(.plain))
        #expect(plain.probeFrames["a"] == CGRect(x: 8, y: 4, width: 35, height: 16))
        let bordered = runtime(List { Text("Apple")._probe("a") }.listStyle(.bordered))
        #expect(bordered.probeFrames["a"] == CGRect(x: 7, y: 5, width: 35, height: 16))
        let sidebar = runtime(List { Text("Apple")._probe("a") }.listStyle(.sidebar))
        #expect(sidebar.probeFrames["a"]?.origin == CGPoint(x: 16, y: 10 + (32 - 18.5) / 2))
        #expect(sidebar.render(scale: 2).commands.first?.description == "fillRect(0, 0, 320, 200) #F0F0F0")
    }

    @Test func pressesSelectRows() {
        let box = _SelectionBox()
        let binding = Binding<Int?>(get: { box.value }, set: { box.value = $0 })
        let r = runtime(List(Self.items, selection: binding) { Text($0.name)._probe("item\($0.id)") })
        #expect(r.probeFrames["item2"] == CGRect(x: 16, y: 38, width: 45, height: 16))
        r.pointerDown(at: CGPoint(x: 100, y: 45)); r.pointerUp(at: CGPoint(x: 100, y: 45))
        #expect(box.value == 2)
        r.layout(in: CGSize(width: 320, height: 200))
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains("fillRRect(10, 34, 300, 24) r=7 #000000@\(35.0 / 255)"))
        // Separators next to the selected row disappear; pressing again deselects.
        #expect(!commands.contains { $0.hasPrefix("fillRect(16, 33") } && !commands.contains { $0.hasPrefix("fillRect(16, 57") })
        r.pointerDown(at: CGPoint(x: 100, y: 45)); r.pointerUp(at: CGPoint(x: 100, y: 45))
        #expect(box.value == nil)
        // Multiple selection accumulates.
        let set = _SetBox()
        let multi = runtime(List(Self.items, selection: Binding<Set<Int>>(get: { set.value }, set: { set.value = $0 })) { Text($0.name) })
        multi.pointerDown(at: CGPoint(x: 100, y: 20)); multi.pointerUp(at: CGPoint(x: 100, y: 20))
        multi.pointerDown(at: CGPoint(x: 100, y: 70)); multi.pointerUp(at: CGPoint(x: 100, y: 70))
        #expect(set.value == [1, 3])
    }
}

private final class _SelectionBox: @unchecked Sendable { var value: Int? = nil }
private final class _SetBox: @unchecked Sendable { var value: Set<Int> = [] }
#endif
