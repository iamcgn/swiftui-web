// draggable / dropDestination: a press that moves lifts the payload, the preview follows the
// pointer, destinations under it are targeted, a release delivers the value (converted through
// the payload's representations when the destination wants another type).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct DragDropTests {
    final class Log {
        var dropped: [(String, CGPoint)] = []
        var targeted: [Bool] = []
        var names: [String] = []
    }

    struct Person: Transferable {
        var name: String
        static var transferRepresentation: some TransferRepresentation<Person> {
            ProxyRepresentation(exporting: \.name)
        }
    }

    struct Board: View {
        let log: Log
        var body: some View {
            HStack(spacing: 40) {
                Color.red.frame(width: 40, height: 40).draggable("hello")._probe("source")
                Color.blue.frame(width: 80, height: 80)
                    .dropDestination(for: String.self, action: { items, point in log.dropped.append((items[0], point)); return true },
                                     isTargeted: { log.targeted.append($0) })
                    ._probe("target")
                Color.green.frame(width: 40, height: 40).draggable(Person(name: "Ada"))._probe("person")
            }
        }
    }

    static let red = "#FF383C"

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 200))
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 200)) }

    @Test func dragLiftsTargetsAndDrops() {
        let log = Log()
        let r = runtime(Board(log: log))
        let source = r.probeFrames["source"]!, target = r.probeFrames["target"]!
        #expect(source == CGRect(x: 40, y: 80, width: 40, height: 40) && target == CGRect(x: 120, y: 60, width: 80, height: 80))
        r.pointerDown(at: CGPoint(x: 50, y: 90))
        r.pointerMoved(to: CGPoint(x: 52, y: 90))
        #expect(!r.isDragging)                                  // under the 4 pt threshold
        r.pointerMoved(to: CGPoint(x: 60, y: 100))
        #expect(r.isDragging)
        // The preview paints at the pointer minus the grab offset (10, 10), at 0.8 opacity.
        let lifted = commands(r)
        #expect(lifted.contains("beginGroup(opacity: 0.8)") && lifted.contains("fillRect(50, 90, 40, 40) \(Self.red)"))
        #expect(log.targeted.isEmpty)
        r.pointerMoved(to: CGPoint(x: 150, y: 100))
        relayout(r)
        #expect(log.targeted == [true])
        r.pointerMoved(to: CGPoint(x: 250, y: 100))
        #expect(log.targeted == [true, false])
        r.pointerMoved(to: CGPoint(x: 160, y: 120))
        r.pointerUp(at: CGPoint(x: 160, y: 120))
        #expect(!r.isDragging)
        #expect(log.dropped.count == 1 && log.dropped[0].0 == "hello" && log.dropped[0].1 == CGPoint(x: 40, y: 60))
        #expect(log.targeted == [true, false, true, false])
        #expect(!commands(r).contains("beginGroup(opacity: 0.8)"))
    }

    @Test func dropOutsideCancels() {
        let log = Log()
        let r = runtime(Board(log: log))
        r.pointerDown(at: CGPoint(x: 50, y: 90))
        r.pointerMoved(to: CGPoint(x: 70, y: 90))
        r.pointerUp(at: CGPoint(x: 70, y: 20))
        #expect(!r.isDragging && log.dropped.isEmpty && log.targeted.isEmpty)
    }

    @Test func proxyRepresentationConverts() {
        let log = Log()
        let r = runtime(Board(log: log))
        let person = r.probeFrames["person"]!
        r.pointerDown(at: CGPoint(x: person.midX, y: person.midY))
        r.pointerMoved(to: CGPoint(x: person.midX - 20, y: person.midY))
        r.pointerMoved(to: CGPoint(x: 150, y: 100))
        r.pointerUp(at: CGPoint(x: 150, y: 100))
        #expect(log.dropped.map(\.0) == ["Ada"])
        let item = _TransferItem(Person(name: "Grace"))
        #expect(item.load(as: String.self) == "Grace")
        #expect(item.load(as: Data.self) == nil)
        #expect(_TransferItem("x").load(as: Data.self) == Data("x".utf8))
    }
}
#endif
