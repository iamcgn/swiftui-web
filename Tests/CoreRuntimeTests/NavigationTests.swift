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
