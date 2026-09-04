// Menu: the pull-down button's sizes (plain, split, no indicator), presenting the content as a
// menu on a press, rows and separators, activation dismissing every menu, submenus and context
// menus. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct MenuTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Options", 47.5), ("Cut", 21.5), ("Copy", 31.5), ("More", 31.0), ("Paste", 34.0), ("Primary", 46.5),
                              ("Hidden", 43.5), ("Action", 39.0), ("Hi", 12.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
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

    private func press(_ r: Runtime, at point: CGPoint) {
        r.pointerDown(at: point)
        r.pointerUp(at: point)
        r.layout(in: CGSize(width: 320, height: 200))
    }

    private func texts(_ r: Runtime) -> [String] {
        r.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("drawText(") }.map { String($0.dropFirst(10).prefix { $0 != "\"" }) }
    }

    @Test func pullDownSizes() {
        let r = runtime(VStack {
            Menu("Options") { Button("Cut") {} }._probe("plain")
            Menu("Primary") { Button("Cut") {} } primaryAction: {}
                ._probe("split")
            Menu("Hidden") { Button("Cut") {} }.menuIndicator(.hidden)._probe("noIndicator")
        })
        // The pop-up button's box: 12 inset, the label, 18 to a 7 pt chevron, 10.5 trailing; 24 tall.
        #expect(r.probeFrames["plain"]?.size == CGSize(width: 95, height: 24))
        // Split: 8 to a 1 pt divider, 24 to the trailing edge.
        #expect(r.probeFrames["split"]?.size == CGSize(width: 91.5, height: 24))
        // No indicator: the inset on both sides.
        #expect(r.probeFrames["noIndicator"]?.size == CGSize(width: 67.5, height: 24))
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("fillRRect(112.5, ") && $0.contains("r=6 #000000@\(20.0 / 255)") })
        #expect(commands.contains { $0.hasPrefix("drawText(\"Options\" system 13 w400 at 124.5,") })
        // The split button's divider, 5 pt in from the top and bottom.
        #expect(commands.contains { $0.hasPrefix("fillRect(180.75, ") && $0.contains("1, 14) #000000@0.12") } || commands.contains { $0.contains(", 1, 14) #000000@0.12") })
    }

    @Test func pressPresentsRowsAndSeparators() {
        let box = _MenuBox()
        let r = runtime(Menu("Options") {
            Button("Cut") { box.last = "Cut" }
            Divider()
            Button("Copy") { box.last = "Copy" }
        }._probe("menu"))
        let button = r.probeFrames["menu"]!
        #expect(button == CGRect(x: 112.5, y: 88, width: 95, height: 24))
        #expect(!texts(r).contains("Cut"))
        press(r, at: CGPoint(x: button.midX, y: button.midY))
        #expect(r.presentations.count == 1 && r.presentations.first?.kind == .menu)
        // The menu hangs 2 pt under the button, rows 22 tall, the separator 11, 4 pt above and below.
        let panel = r.presentations.first!.panel
        #expect(panel.origin == CGPoint(x: 112.5, y: 114))
        #expect(panel.size == CGSize(width: 92.5, height: 22 + 11 + 22 + 8))
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(texts(r).contains("Cut") && texts(r).contains("Copy"))
        // The row's title sits after the 22 pt check column.
        #expect(commands.contains { $0.hasPrefix("drawText(\"Cut\" system 13 w400 at 134.5,") })
        #expect(commands.contains { $0.hasPrefix("fillRect(120.5, 145, 76.5, 1) #000000@0.1") })
        // The rows are buttons in the accessibility tree (the overlay drives them).
        #expect(r.semanticsTree().map { "\($0.role):\($0.label)" } == ["popUpButton:Options", "button:Cut", "button:Copy"])
        // Pressing a row runs its action and closes the menu.
        press(r, at: CGPoint(x: panel.midX, y: panel.minY + 4 + 11 + 22 + 11))
        #expect(box.last == "Copy")
        #expect(r.presentations.isEmpty)
        // A press outside closes it without running anything.
        press(r, at: CGPoint(x: button.midX, y: button.midY))
        press(r, at: CGPoint(x: 5, y: 5))
        #expect(r.presentations.isEmpty && box.last == "Copy")
    }

    @Test func primaryActionSplitsTheButton() {
        let box = _MenuBox()
        let r = runtime(Menu("Primary") { Button("Cut") { box.last = "Cut" } } primaryAction: { box.count += 1 }._probe("menu"))
        let button = r.probeFrames["menu"]!
        press(r, at: CGPoint(x: button.minX + 20, y: button.midY))
        #expect(box.count == 1 && r.presentations.isEmpty)
        press(r, at: CGPoint(x: button.maxX - 8, y: button.midY))
        #expect(box.count == 1 && r.presentations.count == 1)
    }

    @Test func submenusOpenBesideTheirRow() {
        let box = _MenuBox()
        let r = runtime(Menu("Options") {
            Button("Cut") { box.last = "Cut" }
            Menu("More") { Button("Paste") { box.last = "Paste" } }
        }._probe("menu"))
        let button = r.probeFrames["menu"]!
        press(r, at: CGPoint(x: button.midX, y: button.midY))
        let panel = r.presentations.first!.panel
        #expect(texts(r).contains("More") && !texts(r).contains("Paste"))
        press(r, at: CGPoint(x: panel.minX + 30, y: panel.minY + 4 + 22 + 11))
        #expect(r.presentations.count == 2 && r.presentations.last?.kind == .submenu)
        let sub = r.presentations.last!.panel
        #expect(sub.minX == panel.maxX && sub.minY == panel.minY + 4 + 22 - 4)
        #expect(texts(r).contains("Paste"))
        // Activating a submenu item closes both menus.
        press(r, at: CGPoint(x: sub.midX, y: sub.midY))
        #expect(box.last == "Paste" && r.presentations.isEmpty)
    }

    @Test func contextMenusOpenAtThePointer() {
        let box = _MenuBox()
        let r = runtime(Text("Hi").contextMenu { Button("Action") { box.last = "Action" } }._probe("text"))
        let text = r.probeFrames["text"]!
        r.secondaryPointerDown(at: CGPoint(x: 40, y: 40))
        #expect(r.presentations.isEmpty)
        r.secondaryPointerDown(at: CGPoint(x: text.midX, y: text.midY))
        r.layout(in: CGSize(width: 320, height: 200))
        #expect(r.presentations.count == 1)
        let panel = r.presentations.first!.panel
        #expect(panel.origin == CGPoint(x: text.midX, y: text.midY + 2))
        #expect(texts(r).contains("Action"))
        press(r, at: CGPoint(x: panel.midX, y: panel.midY))
        #expect(box.last == "Action" && r.presentations.isEmpty)
    }
}

private final class _MenuBox: @unchecked Sendable {
    var last = ""
    var count = 0
}
#endif
