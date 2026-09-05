// openWindow / dismissWindow / openSettings: window scenes open as floating, non-modal windows
// inside the host; value windows carry their value; the close control and dismissWindow close them.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct WindowTests {
    struct Note: Codable, Hashable { var text: String }

    struct Demo: App {
        var body: some Scene {
            WindowGroup { Text("Main") }
            Window("Inspector", id: "inspector") { Color.red.frame(width: 100, height: 60)._probe("inspector") }
            WindowGroup("Note", for: Note.self) { note in
                Text(note.wrappedValue?.text ?? "empty")._probe("note")
            }
            .defaultSize(width: 200, height: 120)
            Settings { Color.blue.frame(width: 80, height: 40)._probe("settings") }
            MenuBarExtra("Extra") { Text("menu") }
        }
    }

    private func runtime() -> Runtime {
        let runtime = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let regular = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        let semibold = ResolvedFont(family: "system", size: 13, weight: .semibold, italic: false, textStyle: nil)
        for word in ["Main", "hello", "world", "empty", "menu"] {
            entries[RecordedTextEngine.key(font: regular, width: nil, string: word)] = .init(width: 40, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        entries[RecordedTextEngine.key(font: semibold, width: nil, string: "Inspector")] = .init(width: 60, height: 16, firstBaseline: 13, lastBaseline: 13)
        entries[RecordedTextEngine.key(font: semibold, width: nil, string: "Note")] = .init(width: 30, height: 16, firstBaseline: 13, lastBaseline: 13)
        entries[RecordedTextEngine.key(font: semibold, width: nil, string: "Settings")] = .init(width: 50, height: 16, firstBaseline: 13, lastBaseline: 13)
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.installWindows(Demo._windows())
        runtime.mount(Demo._rootView())
        runtime.layout(in: CGSize(width: 600, height: 400))
        return runtime
    }

    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 600, height: 400)) }
    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }

    @Test func scenesAreRegistered() {
        let windows = Demo._windows()
        #expect(windows.map(\.kind) == [.windowGroup, .window, .windowGroup, .settings, .menuBarExtra])
        #expect(windows[1].id == "inspector" && windows[1].title == "Inspector")
        #expect(windows[2].defaultSize == CGSize(width: 200, height: 120) && windows[2].valueType == Note.self)
    }

    @Test func openWindowByIdAndClose() {
        let r = runtime()
        #expect(r.openWindow(id: "inspector", value: nil))
        relayout(r)
        #expect(r.openWindowCount == 1 && r.hasPresentations)
        // Content is laid out inside a floating panel with a 28 pt title bar and 20 pt padding, centred.
        let inspector = r.probeFrames["inspector"]!
        #expect(inspector.size == CGSize(width: 100, height: 60))
        // Panel 140 × 128 (content + padding + bar) centred in 600 × 400: content at (250, 184).
        #expect(inspector.minX == 250 && inspector.minY == 184)
        // Opening again brings the same window forward rather than a second one.
        #expect(r.openWindow(id: "inspector", value: nil) && r.openWindowCount == 1)
        // The title is painted; the traffic lights are three circles.
        let painted = commands(r)
        #expect(painted.contains { $0.hasPrefix("drawText(\"Inspector\"") })
        // A click on the close control (13 pt in, centred in the bar) closes it.
        let panel = CGPoint(x: inspector.minX - 20, y: inspector.minY - 20 - 28)
        r.pointerDown(at: CGPoint(x: panel.x + 19, y: panel.y + 14))
        r.pointerUp(at: CGPoint(x: panel.x + 19, y: panel.y + 14))
        relayout(r)
        #expect(r.openWindowCount == 0 && !r.hasPresentations)
    }

    @Test func valueWindowsCarryTheirValue() {
        let r = runtime()
        #expect(r.openWindow(id: nil, value: Note(text: "hello")))
        #expect(r.openWindow(id: nil, value: Note(text: "world")))
        relayout(r)
        #expect(r.openWindowCount == 2)
        let texts = commands(r).filter { $0.hasPrefix("drawText(\"hello\"") || $0.hasPrefix("drawText(\"world\"") }
        #expect(texts.count == 2)
        // The same value opens no second window; another id does not match.
        #expect(r.openWindow(id: nil, value: Note(text: "hello")) && r.openWindowCount == 2)
        #expect(!r.openWindow(id: "missing", value: nil))
        r.dismissWindow(id: nil, value: Note(text: "hello"))
        relayout(r)
        #expect(r.openWindowCount == 1)
        r.dismissWindow(id: nil, value: nil)
        relayout(r)
        #expect(r.openWindowCount == 0)
    }

    @Test func settingsAndNonModality() {
        let r = runtime()
        r.openSettings()
        relayout(r)
        #expect(r.openWindowCount == 1 && r.probeFrames["settings"] != nil)
        // A press beside the window does not close it (windows are not modal).
        r.pointerDown(at: CGPoint(x: 10, y: 10))
        r.pointerUp(at: CGPoint(x: 10, y: 10))
        relayout(r)
        #expect(r.openWindowCount == 1)
        r.openSettings()
        #expect(r.openWindowCount == 1)
    }
}
#endif
