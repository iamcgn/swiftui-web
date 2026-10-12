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

    // MARK: Across the app boundary (sw-dragdrop-os)

    /// A note with a JSON representation and a file representation.
    struct Note: Codable, Transferable, Equatable {
        var text: String
        static var transferRepresentation: some TransferRepresentation<Note> {
            CodableRepresentation(contentType: .json)
            FileRepresentation(contentType: .plainText,
                               exporting: { note in SentTransferredFile(_TransferItem.storeFile(Data(note.text.utf8), name: "note.txt")) },
                               importing: { received in Note(text: String(decoding: try Data(contentsOf: received.file), as: UTF8.self)) })
        }
    }

    final class NoteLog {
        var notes: [Note] = []
        var urls: [URL] = []
        var inserted: [(Int, [String])] = []
        var targeted: [Bool] = []
    }

    struct NoteBoard: View {
        let log: NoteLog
        var body: some View {
            HStack(spacing: 40) {
                Color.red.frame(width: 40, height: 40).draggable(Note(text: "Buy milk"))._probe("note")
                Color.blue.frame(width: 80, height: 80)
                    .dropDestination(for: Note.self, action: { notes, _ in log.notes += notes; return true })
                    ._probe("notes")
                Color.green.frame(width: 40, height: 40)
                    .dropDestination(for: URL.self, action: { urls, _ in log.urls += urls; return true })
                    ._probe("urls")
            }
        }
    }

    /// The app's own drag is handed to the host as items: the text, the JSON under its type,
    /// the file with its name and bytes; the preview renders for the system's drag image.
    @Test func externalItemsOfAnAppDrag() {
        let log = NoteLog()
        let r = runtime(NoteBoard(log: log))
        #expect(r.externalDragItems().isEmpty && !r.hasDragSource(at: CGPoint(x: 150, y: 100)) && r.hasDragSource(at: CGPoint(x: 50, y: 90)))
        r.pointerDown(at: CGPoint(x: 50, y: 90))
        // The browser's dragstart comes before the scene's own threshold: the payload lifts now.
        let items = r.beginExternalDrag(at: CGPoint(x: 51, y: 90))
        #expect(r.isDragging)
        #expect(items.map(\.type) == ["application/json", "text/plain"])
        #expect(items[0].text == "{\"text\":\"Buy milk\"}" && items[0].data == Data("{\"text\":\"Buy milk\"}".utf8))
        #expect(items[1].fileName == "note.txt" && items[1].data == Data("Buy milk".utf8))
        let preview = r.externalDragPreview()
        #expect(preview?.size == CGSize(width: 40, height: 40) && preview?.grab == CGPoint(x: 10, y: 10))
        #expect(preview?.list.commands.map(\.description).contains("fillRect(0, 0, 40, 40) \(Self.red)") == true)
        // While the system carries it the scene paints no preview of its own, but still targets.
        #expect(!commands(r).contains("beginGroup(opacity: 0.8)"))
        #expect(r.externalDragUpdated(types: ["application/json"], at: CGPoint(x: 150, y: 100)))
        #expect(!r.externalDragUpdated(types: ["application/json"], at: CGPoint(x: 250, y: 20)))
        // Dropped in another app: the drag is over, nothing delivered here.
        r.externalDragEnded(dropped: true)
        #expect(!r.isDragging && log.notes.isEmpty)
        // Dropped back on the scene: the destination takes it.
        r.pointerDown(at: CGPoint(x: 50, y: 90))
        _ = r.beginExternalDrag(at: CGPoint(x: 51, y: 90))
        #expect(r.externalDrop(items: [], at: CGPoint(x: 150, y: 100)))
        #expect(log.notes == [Note(text: "Buy milk")] && !r.isDragging)
    }

    /// A drag from outside: its types target the destinations before any data arrives; the
    /// drop delivers JSON through the codable importer, a file through the file importer, a
    /// URL list as URLs; plain text is not JSON.
    @Test func dropsFromOutside() {
        let log = NoteLog()
        let r = runtime(NoteBoard(log: log))
        // Plain text is announced as acceptable (a text file imports as a note) but a text
        // drop without a file is not a note; the drag from outside ends when it leaves.
        #expect(r.externalDragUpdated(types: ["text/plain"], at: CGPoint(x: 150, y: 100)))
        #expect(r.isDragging)
        r.externalDragExited()
        #expect(!r.isDragging)
        #expect(!r.externalDrop(items: [ExternalDragItem(type: "text/plain", text: "not json")], at: CGPoint(x: 150, y: 100)))
        #expect(!r.externalDragUpdated(types: ["image/png"], at: CGPoint(x: 150, y: 100)))
        r.externalDragExited()
        #expect(r.externalDragUpdated(types: ["application/json"], at: CGPoint(x: 150, y: 100)))
        #expect(r.externalDrop(items: [ExternalDragItem(type: "application/json", text: "{\"text\":\"Call Bob\"}")], at: CGPoint(x: 150, y: 100)))
        #expect(log.notes == [Note(text: "Call Bob")])
        // A dropped text file imports through the file representation.
        #expect(r.externalDrop(items: [ExternalDragItem(type: "text/plain", data: Data("From a file".utf8), fileName: "todo.txt")], at: CGPoint(x: 150, y: 100)))
        #expect(log.notes.last == Note(text: "From a file"))
        // A URL list drops on the URL destination, not the note one.
        #expect(!r.externalDragUpdated(types: ["text/uri-list"], at: CGPoint(x: 150, y: 100)))
        #expect(r.externalDrop(items: [ExternalDragItem(type: "text/uri-list", text: "https://example.com/a\r\nhttps://example.com/b")], at: CGPoint(x: 250, y: 100)))
        #expect(log.urls == [URL(string: "https://example.com/a")!])
    }

    struct Rows: View {
        let log: NoteLog
        @State private var names = ["Ada", "Grace"]
        var body: some View {
            List {
                ForEach(names, id: \.self) { name in Text(name)._probe(name) }
                    .dropDestination(for: String.self, action: { items, offset in log.inserted.append((offset, items)) },
                                     isTargeted: { log.targeted.append($0) })
            }
            ._probe("list")
        }
    }

    /// A drop between a list's rows: the offset follows the row middles, the insertion line is
    /// painted at the row edge, the action gets the values and the offset.
    @Test func dropsBetweenListRows() {
        let log = NoteLog()
        let r = runtime(Rows(log: log))
        let ada = r.probeFrames["Ada"]!, grace = r.probeFrames["Grace"]!
        // The texts are zero-sized without a text engine: their frames mark the row middles.
        #expect(r.externalDragUpdated(types: ["text/plain"], at: CGPoint(x: 100, y: grace.midY - 5)))
        #expect(log.targeted == [true])
        let painted = commands(r)
        #expect(painted.contains { $0.hasPrefix("fillRect(") && $0.contains(", 2) ") && $0.contains("#") }, "an insertion line")
        r.externalDrop(items: [ExternalDragItem(type: "text/plain", text: "Linus")], at: CGPoint(x: 100, y: grace.midY - 5))
        #expect(log.inserted.count == 1 && log.inserted[0].0 == 1 && log.inserted[0].1 == ["Linus"])
        #expect(log.targeted == [true, false])
        r.externalDrop(items: [ExternalDragItem(type: "text/plain", text: "Top")], at: CGPoint(x: 100, y: ada.midY - 5))
        #expect(log.inserted.last?.0 == 0)
        r.externalDrop(items: [ExternalDragItem(type: "text/plain", text: "End")], at: CGPoint(x: 100, y: grace.midY + 8))
        #expect(log.inserted.last?.0 == 2)
    }
}
#endif
