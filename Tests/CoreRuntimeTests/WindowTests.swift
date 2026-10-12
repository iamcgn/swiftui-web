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

    /// sw-windows: the scene modifiers with effect (a default position, no title bar, no
    /// resize), dragging a window by its bar and resizing it by its grip, the key window
    /// keeping Tab, commands' shortcuts and the menu-bar description, document windows
    /// (new, open through the host, save through the host) and restoration.
    @MainActor final class Log { var log: [String] = []; var stored: String? }

    struct Doc: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText] }
        var text: String
        init(text: String) { self.text = text }
        init(configuration: FileDocumentReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
        func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
    }

    struct Rich: App {
        static let log = Log()
        var body: some Scene {
            DocumentGroup(newDocument: Doc(text: "hello")) { config in
                Button(config.document.text) { config.document.text += "!" }._probe("doc")
            }
            .commands {
                CommandMenu("Tools") {
                    Button("Tool") { Rich.log.log.append("tool") }.keyboardShortcut("t")
                    Divider()
                    Button("Other") { Rich.log.log.append("other") }.disabled(true)
                }
                CommandGroup(after: .help) { Button("Guide") { Rich.log.log.append("guide") } }
            }
            Window("Palette", id: "palette") { Color.red.frame(width: 100, height: 60)._probe("palette") }
                .defaultPosition(.topLeading)
                .windowResizability(.contentSize)
                .windowStyle(.hiddenTitleBar)
            Window("Tools", id: "tools") { Button("Press") { Rich.log.log.append("press") }._probe("press") }
        }
    }

    @Test func modifiersDraggingCommandsAndDocuments() {
        let r = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let regular = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        let semibold = ResolvedFont(family: "system", size: 13, weight: .semibold, italic: false, textStyle: nil)
        for word in ["hello", "hello!", "Press", "Tool", "Other", "Guide", "New", "Open…", "Save", "Save As…", "from file"] {
            entries[RecordedTextEngine.key(font: regular, width: nil, string: word)] = .init(width: 40, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        for word in ["Palette", "Tools"] { entries[RecordedTextEngine.key(font: semibold, width: nil, string: word)] = .init(width: 50, height: 16, firstBaseline: 13, lastBaseline: 13) }
        r.textEngine = RecordedTextEngine(entries: entries)
        let log = Rich.log
        r.windowStateStore = (get: { log.stored }, set: { log.stored = $0 })
        r.installWindows(Rich._windows())
        r.mount(Rich._rootView())
        relayout(r)
        // The main window shows the new document; its button edits it through the binding.
        let doc = r.probeFrames["doc"]!
        r.pointerDown(at: CGPoint(x: doc.midX, y: doc.midY)); r.pointerUp(at: CGPoint(x: doc.midX, y: doc.midY))
        relayout(r)
        #expect((r.frontmostDocument as? _DocumentState<Doc>)?.document?.text == "hello!")
        // The palette: top-leading at the 20 pt margin, no title bar (content 20 in), no grip.
        #expect(r.openWindow(id: "palette", value: nil))
        relayout(r)
        let palette = r.probeFrames["palette"]!
        #expect(palette.minX == 40 && palette.minY == 40, "\(palette)")
        let paletteNode = r.presentations.last!
        #expect(!paletteNode.windowOptions.resizable && paletteNode.windowOptions.hidesTitleBar && paletteNode.titleBarHeight == 0)
        // The tools window: dragging its bar moves it; its grip resizes it; it is the key window.
        #expect(r.openWindow(id: "tools", value: nil))
        relayout(r)
        let tools = r.presentations.last!
        let bar = CGPoint(x: tools.panel.maxX - 10, y: tools.panel.minY + 14)   // the bar's draggable part is beside the lights
        let before = tools.panel
        r.pointerDown(at: bar)
        #expect(r.keyWindow === tools, "\(tools.panel) \(bar) \(tools.dragBarFrame) \(r.interactiveNode(at: bar).map { $0.nodeDescription } as Any)")
        r.pointerMoved(to: CGPoint(x: bar.x + 30, y: bar.y + 10)); r.pointerUp(at: CGPoint(x: bar.x + 30, y: bar.y + 10))
        relayout(r)
        #expect(tools.panel.minX == before.minX + 30 && tools.panel.minY == before.minY + 10, "\(before) \(tools.panel)")
        let grip = CGPoint(x: tools.panel.maxX - 6, y: tools.panel.maxY - 6)
        r.pointerMoved(to: grip)
        #expect(r.pointerStyle == .frameResize(position: .bottomTrailing))
        r.pointerDown(at: grip); r.pointerMoved(to: CGPoint(x: grip.x + 40, y: grip.y + 20)); r.pointerUp(at: CGPoint(x: grip.x + 40, y: grip.y + 20))
        let sized = tools.panel
        relayout(r)
        #expect(tools.panel.width == sized.width + 40 && tools.panel.height == sized.height + 20, "\(sized) \(tools.panel)")
        #expect(r.keyWindow === tools)
        // Tab stays in the key window: its only control.
        #expect(r.moveFocus(forward: true) && r.focusedIdentifier == r.semanticsTree().first { $0.label == "Press" }?.identifier)
        // Commands: ⌘T runs the menu's button; the description carries titles, shortcuts, enabled states and the document commands.
        #expect(r.keyDown(KeyEvent(key: KeyEquivalent("t"), modifiers: [.command])) && log.log == ["tool"])
        let menus = r.commandMenus
        #expect(menus.map(\.title) == ["File", "Tools", "Help"], "\(menus.map(\.title))")
        #expect(menus[0].items.compactMap(\.label) == ["New", "Open…", "Save", "Save As…"] && menus[0].items.contains { $0.label == nil })
        #expect(menus[1].items.map { $0.label ?? "-" } == ["Tool", "-", "Other"] && menus[1].items[2].isEnabled == false && menus[1].items[0].shortcut?.key == KeyEquivalent("t"))
        r.performCommand(identifier: menus[2].items[0].identifier)
        #expect(log.log == ["tool", "guide"])
        // Documents: New opens another window; Open goes through the host and reads the bytes;
        // Save hands the frontmost document's bytes and name to the host.
        var saved: (Data, String)?
        r.documentSaveHandler = { data, name, _, _ in saved = (data, name); return nil }
        r.documentOpenHandler = { types, completion in #expect(types == [.plainText]); completion(Data("from file".utf8), "notes.txt", nil) }
        #expect(r.newDocument())
        relayout(r)
        #expect(r.openWindows.count == 3)
        #expect(r.openDocument())
        relayout(r)
        #expect((r.frontmostDocument as? _DocumentState<Doc>)?.document?.text == "from file")
        #expect(r.saveDocument() && saved?.1 == "notes.txt" && saved.map { String(decoding: $0.0, as: UTF8.self) } == "from file")
        // Restoration: the id windows are remembered; a fresh runtime reopens them.
        #expect(log.stored?.contains("id=palette") == true && log.stored?.contains("id=tools") == true)
        let again = Runtime()
        again.textEngine = r.textEngine
        again.windowStateStore = (get: { log.stored }, set: { _ in })
        again.installWindows(Rich._windows())
        again.mount(Rich._rootView())
        again.restoreWindows()
        again.layout(in: CGSize(width: 600, height: 400))
        #expect(again.openWindows.contains { $0.descriptor.id == "palette" } && again.openWindows.contains { $0.descriptor.id == "tools" })
    }
}
#endif
