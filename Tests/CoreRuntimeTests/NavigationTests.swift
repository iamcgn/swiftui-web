// NavigationStack (Phase 2): pushing through links (value and destination forms), the path
// binding, popping, navigationDestination(isPresented:), links as list rows, the title.
// Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct NavigationTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Root", 28.5), ("Push", 30.0), ("Detail", 35.0), ("Number 1", 58.0), ("Number 2", 60.0), ("Apple", 35.0), ("Deeper", 44.5)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func texts(_ r: Runtime) -> [String] {
        r.render(scale: 2).commands.map(\.description).compactMap { command in
            guard command.hasPrefix("drawText(\"") else { return nil }
            return String(command.dropFirst(10).prefix { $0 != "\"" })
        }
    }

    @Test func valueLinksPushThroughThePathBinding() {
        let box = _PathBox()
        let r = runtime(NavigationStack(path: Binding(get: { box.path }, set: { box.path = $0 })) {
            VStack(spacing: 12) {
                Text("Root")._probe("root")
                NavigationLink("Push", value: 1)._probe("link")
            }
            .navigationDestination(for: Int.self) { number in
                VStack(spacing: 12) {
                    Text("Number \(number)")._probe("number\(number)")
                    NavigationLink("Deeper", value: number + 1)
                }
            }
        }._probe("nav"))
        // The stack is its root's size, centred; the link is a bordered button.
        #expect(r.probeFrames["nav"] == CGRect(x: 133, y: 74, width: 54, height: 52))
        #expect(r.probeFrames["link"] == CGRect(x: 133, y: 102, width: 54, height: 24))
        #expect(texts(r) == ["Root", "Push"])
        r.pointerDown(at: CGPoint(x: 160, y: 114)); r.pointerUp(at: CGPoint(x: 160, y: 114))
        #expect(box.path == [1])
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Number 1", "Deeper"])
        // The pushed view is centred; the root stays laid out beneath it.
        #expect(r.probeFrames["number1"] == CGRect(x: 131, y: 74, width: 58, height: 16))
        #expect(r.probeFrames["root"] == CGRect(x: 145.75, y: 74, width: 28.5, height: 16))
        // Pressing the pushed link goes deeper; the model pops back.
        r.pointerDown(at: CGPoint(x: 160, y: 114)); r.pointerUp(at: CGPoint(x: 160, y: 114))
        #expect(box.path == [1, 2])
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r).first == "Number 2")
        box.path = []
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Root", "Push"])
    }

    @Test func destinationLinksAndBackWithoutABinding() {
        let r = runtime(NavigationStack {
            NavigationLink("Detail") { Text("Number 1") }
        })
        #expect(texts(r) == ["Detail"])
        r.pointerDown(at: CGPoint(x: 160, y: 100)); r.pointerUp(at: CGPoint(x: 160, y: 100))
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Number 1"])
        #expect(r.navigateBack())
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Detail"])
        #expect(!r.navigateBack())
    }

    @Test func navigationPathAndPresentedDestination() {
        let box = _NavigationPathBox()
        let flag = _FlagBox()
        let r = runtime(NavigationStack(path: Binding(get: { box.path }, set: { box.path = $0 })) {
            Text("Root")
                .navigationDestination(for: String.self) { Text($0) }
                .navigationDestination(isPresented: Binding(get: { flag.value }, set: { flag.value = $0 })) { Text("Detail") }
                .navigationTitle("Title")
        })
        #expect(r.navigationTitle == "Title")
        box.path.append("Apple")
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Apple"])
        #expect(box.path.count == 1)
        // Values without a registered destination are ignored.
        box.path.append(7)
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Apple"])
        box.path.removeLast(2)
        flag.value = true
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Detail"])
        #expect(r.navigateBack())
        #expect(flag.value == false)
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(texts(r) == ["Root"])
    }

    @Test func listRowsPush() {
        let box = _PathBox()
        let r = runtime(NavigationStack(path: Binding(get: { box.path }, set: { box.path = $0 })) {
            List {
                NavigationLink("Apple", value: 1)._probe("row")
            }
            .navigationDestination(for: Int.self) { Text("Number \($0)") }
        })
        // A plain row, no button chrome.
        #expect(r.probeFrames["row"] == CGRect(x: 16, y: 14, width: 35, height: 16))
        r.pointerDown(at: CGPoint(x: 200, y: 20)); r.pointerUp(at: CGPoint(x: 200, y: 20))
        #expect(box.path == [1])
    }
}

@Observable private final class _PathBox: @unchecked Sendable { var path: [Int] = [] }
@Observable private final class _NavigationPathBox: @unchecked Sendable { var path = NavigationPath() }
@Observable private final class _FlagBox: @unchecked Sendable { var value = false }
#endif

// MARK: - Phase 8 step 6, sw-navigation

@Observable
private final class ItemModel {
    var item: String? = nil
    var path: [Int] = []
    var presented = false
}

private struct ItemStack: View {
    let model: ItemModel
    var body: some View {
        NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
            VStack {
                Text("Root")._probe("root")
                NavigationLink("Push", value: 1)._probe("link")
            }
            .navigationDestination(for: Int.self) { number in Text("Number \(number)")._probe("number\(number)") }
            .navigationDestination(item: Binding(get: { model.item }, set: { model.item = $0 })) { item in Text("Item \(item)")._probe("item\(item)") }
            .navigationDestination(isPresented: Binding(get: { model.presented }, set: { model.presented = $0 })) { Text("Presented")._probe("presented") }
        }
    }
}

/// Internal, not private: the codable representation names types by their mangled names, which
/// `_typeByName` resolves for types without a private discriminator.
struct NavigationPayload: Hashable, Codable {
    var id: Int
    var name: String
}

@Suite @MainActor struct NavigationGapTests {
    private let size = CGSize(width: 320, height: 200)

    @Test func itemDestinationPushesSwapsAndPops() {
        let model = ItemModel()
        let runtime = Runtime()
        runtime.mount(ItemStack(model: model))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["root"] != nil && runtime.probeFrames["itemA"] == nil)
        let stack = runtime.root.descendants(where: { $0 is NavigationStackNode }).first as! NavigationStackNode
        model.item = "A"
        runtime.layout(in: size)
        // Lower screens stay laid out (their probes report); the top screen is the item's.
        #expect(runtime.probeFrames["itemA"] != nil && stack.entries.count == 1)
        model.item = "B"
        runtime.layout(in: size)
        #expect(runtime.probeFrames["itemB"] != nil && runtime.probeFrames["itemA"] == nil && stack.entries.count == 1)
        // Popping clears the item; clearing the item pops.
        stack.pop()
        runtime.layout(in: size)
        #expect(model.item == nil && stack.entries.isEmpty)
        model.item = "C"
        runtime.layout(in: size)
        #expect(runtime.probeFrames["itemC"] != nil && stack.entries.count == 1)
        model.item = nil
        runtime.layout(in: size)
        #expect(stack.entries.isEmpty && runtime.probeFrames["itemC"] == nil)
    }

    @Test func pathChangesKeepTheViewsPushedAboveThem() {
        // nav/path-change: a presented screen over a path stays when the path clears beneath it.
        let model = ItemModel()
        let runtime = Runtime()
        runtime.mount(ItemStack(model: model))
        runtime.layout(in: size)
        model.path = [1]
        runtime.layout(in: size)
        model.presented = true
        runtime.layout(in: size)
        #expect(runtime.probeFrames["presented"] != nil)
        model.path = []
        runtime.layout(in: size)
        let stack = runtime.root.descendants(where: { $0 is NavigationStackNode }).first as! NavigationStackNode
        #expect(runtime.probeFrames["presented"] != nil && runtime.probeFrames["number1"] == nil && stack.entries.count == 1)
        #expect(model.presented)
        // Popping it turns the binding off and shows the root.
        stack.pop()
        runtime.layout(in: size)
        #expect(!model.presented && stack.entries.isEmpty)
    }

    @Test func backShortcutsPopTheStack() {
        let model = ItemModel()
        let runtime = Runtime()
        runtime.mount(ItemStack(model: model))
        runtime.layout(in: size)
        model.path = [1, 2]
        runtime.layout(in: size)
        #expect(runtime.keyDown(KeyEvent(key: KeyEquivalent("["), modifiers: [.command])))
        runtime.layout(in: size)
        #expect(model.path == [1])
        #expect(runtime.keyDown(KeyEvent(key: .escape)))
        runtime.layout(in: size)
        #expect(model.path == [] && runtime.probeFrames["root"] != nil)
        // Nothing to pop: the keys are not consumed.
        #expect(!runtime.keyDown(KeyEvent(key: .escape)))
    }

    @Test func navigationPathRoundTripsThroughItsCodableRepresentation() throws {
        var path = NavigationPath()
        path.append(1)
        path.append("two")
        path.append(NavigationPayload(id: 3, name: "three"))
        let codable = try #require(path.codable)
        #expect(codable.items.count == 6 && codable.items[1] == "{\"id\":3,\"name\":\"three\"}" && codable.items[3] == "\"two\"" && codable.items[5] == "1")
        let data = try _TransferJSONEncoder().encode(codable)
        let decoded = try _TransferJSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: data)
        let restored = NavigationPath(decoded)
        #expect(restored == path)
        #expect(restored.count == 3)
        // An element that is not Codable has no representation.
        struct Plain: Hashable {}
        var plain = NavigationPath()
        plain.append(Plain())
        #expect(plain.codable == nil)
    }
}
