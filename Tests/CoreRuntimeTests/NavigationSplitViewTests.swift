// NavigationSplitView: column geometry (the inset sidebar panel, content column and divider,
// the detail area), column widths, visibility (binding, toggle, ⌃⌘S), lists defaulting to the
// sidebar style, and links in the sidebar driving the detail column. Layout against goldens is
// in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct NavigationSplitViewTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 480, height: 300)) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Detail", 35.0), ("Menu", 34.0), ("Pushed", 44.0), ("Number 1", 58.0), ("Go", 16.0), ("Cherry", 41.5)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        for (word, width) in [("Apple", 35.0), ("Banana", 45.0)] {
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }

    @Test func twoColumns() {
        let r = runtime(NavigationSplitView {
            List { Text("Apple")._probe("row1"); Text("Banana") }._probe("sidebar")
        } detail: {
            Text("Detail")._probe("detail")
        }._probe("split"))
        // macOS 27 (regenerated 2026-10-11): the sidebar is a 144 pt column from the edge, full
        // height, filled (251) with a half-point line after it; the detail starts at its edge
        // with its content centred.
        #expect(r.probeFrames["split"] == CGRect(x: 0, y: 0, width: 480, height: 300))
        #expect(r.probeFrames["sidebar"] == CGRect(x: 0, y: 0, width: 144, height: 300))
        #expect(r.probeFrames["row1"] == CGRect(x: 16, y: 16.75, width: 35, height: 18.5))
        #expect(r.probeFrames["detail"] == CGRect(x: 294.5, y: 142, width: 35, height: 16))
        let node = r.root.descendants(where: { $0 is NavigationSplitViewNode }).first as! NavigationSplitViewNode
        #expect(node.detailFrame == CGRect(x: 144, y: 0, width: 336, height: 300))
        let painted = commands(r)
        #expect(painted.contains { $0.hasPrefix("fillRRect(0, 0, 144, 300) r=0 #FBFBFB") } && painted.contains { $0.hasPrefix("fillRect(144, 0, 0.5, 300) #C9C9C9") }, "\(painted.prefix(3))")
        // The list took the sidebar style (body rows) without its grey background.
        #expect(!painted.contains { $0.contains("#F0F0F0") })
    }

    @Test func threeColumnsAndWidths() {
        let r = runtime(NavigationSplitView {
            VStack { Text("Menu")._probe("menu") }.navigationSplitViewColumnWidth(min: 100, ideal: 120, max: 200)._probe("sidebar")
        } content: {
            List { Text("Cherry")._probe("cherry") }.navigationSplitViewColumnWidth(160)._probe("content")
        } detail: {
            Text("Detail")._probe("detail")
        }, size: CGSize(width: 640, height: 300))
        // Non-list sidebar content is centred in the column (the 144 default: a range's ideal is
        // not taken on macOS 27, only its bounds); a fixed 160 content column follows, then a
        // 1 pt divider, then the detail.
        #expect(r.probeFrames["sidebar"] == CGRect(x: (144 - 34) / 2, y: 142, width: 34, height: 16))
        #expect(r.probeFrames["content"] == CGRect(x: 144, y: 0, width: 160, height: 300))
        #expect(r.probeFrames["cherry"] == CGRect(x: 160, y: 14, width: 41.5, height: 16))
        #expect(r.probeFrames["detail"]?.midX == 472.5)
        #expect(commands(r).contains { $0.hasPrefix("fillRect(304, 0, 1, 300)") })
        // Without a width the content column is 200 wide.
        let plain = runtime(NavigationSplitView {
            Text("Menu")
        } content: {
            Text("Cherry")._probe("cherry")
        } detail: {
            Text("Detail")._probe("detail")
        }, size: CGSize(width: 640, height: 300))
        #expect(plain.probeFrames["cherry"]?.midX == 244.0)
        #expect(plain.probeFrames["detail"]?.midX == 492.5)
    }

    @Observable final class VisibilityModel: @unchecked Sendable { var visibility = NavigationSplitViewVisibility.detailOnly }

    @Test func visibility() {
        let model = VisibilityModel()
        let r = runtime(NavigationSplitView(columnVisibility: Binding(get: { model.visibility }, set: { model.visibility = $0 })) {
            Text("Menu")._probe("menu")
        } detail: {
            Text("Detail")._probe("detail")
        })
        // Detail only: no sidebar, the detail fills the width.
        #expect(r.probeFrames["menu"] == nil)
        #expect(r.probeFrames["detail"]?.midX == 240)
        #expect(!commands(r).contains { $0.hasPrefix("fillRRect(8, 8") })
        model.visibility = .all
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["menu"]?.midX == 72 && r.probeFrames["detail"]?.midX == 312)
        // The toggle and ⌃⌘S go through the binding.
        #expect(r.toggleSidebar() && model.visibility == .detailOnly)
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["detail"]?.midX == 240)
        #expect(r.keyDown(KeyEvent(key: KeyEquivalent("s"), modifiers: [.control, .command])) && model.visibility == .all)
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["detail"]?.midX == 312)
    }

    @Test func ownVisibilityAndThreeColumnDoubleColumn() {
        let r = runtime(NavigationSplitView {
            Text("Menu")._probe("menu")
        } content: {
            Text("Cherry")._probe("cherry")
        } detail: {
            Text("Detail")._probe("detail")
        }, size: CGSize(width: 640, height: 300))
        #expect(r.probeFrames["menu"] != nil && r.probeFrames["cherry"] != nil)
        // Without a binding the split view keeps its own visibility.
        #expect(r.toggleSidebar())
        r.layout(in: CGSize(width: 640, height: 300))
        #expect(r.probeFrames["menu"] == nil && r.probeFrames["cherry"] == nil && r.probeFrames["detail"]?.midX == 320)
        #expect(r.toggleSidebar())
        r.layout(in: CGSize(width: 640, height: 300))
        #expect(r.probeFrames["menu"] != nil && r.probeFrames["cherry"] != nil)
    }

    @Test func sidebarLinksDriveTheDetail() {
        let r = runtime(NavigationSplitView {
            VStack(spacing: 12) {
                NavigationLink("Go") { Text("Pushed")._probe("pushed") }._probe("link")
                NavigationLink("Go", value: 1)._probe("valueLink")
            }
            .navigationDestination(for: Int.self) { number in Text("Number \(number)")._probe("number") }
        } detail: {
            Text("Detail")._probe("detail")
        })
        #expect(r.probeFrames["detail"] != nil && r.probeFrames["pushed"] == nil)
        // A destination link shows its view in the detail column (the detail stays laid out
        // beneath, as in a stack); back pops it; a value link resolves through the registered
        // destination.
        let link = r.probeFrames["link"]!
        r.pointerDown(at: CGPoint(x: link.midX, y: link.midY)); r.pointerUp(at: CGPoint(x: link.midX, y: link.midY))
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["pushed"]?.midX == 312)
        #expect(r.navigateBack())
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["pushed"] == nil && r.probeFrames["detail"]?.midX == 312)
        let valueLink = r.probeFrames["valueLink"]!
        r.pointerDown(at: CGPoint(x: valueLink.midX, y: valueLink.midY)); r.pointerUp(at: CGPoint(x: valueLink.midX, y: valueLink.midY))
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["number"]?.midX == 312)
        #expect(r.navigateBack())
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["number"] == nil)
    }

    /// sw-splitview: dragging the sidebar's divider resizes the column within its range and
    /// shows the column-resize pointer; dragged narrower than half its minimum the sidebar
    /// collapses; the content divider resizes the content column.
    @Test func dividersDragAndCollapse() {
        let model = VisibilityModel()
        model.visibility = .all
        let r = runtime(NavigationSplitView(columnVisibility: Binding(get: { model.visibility }, set: { model.visibility = $0 })) {
            VStack { Text("Menu")._probe("menu") }.navigationSplitViewColumnWidth(min: 100, ideal: 120, max: 200)._probe("sidebar")
        } content: {
            Text("Cherry")._probe("cherry")
        } detail: {
            Text("Detail")._probe("detail")
        }, size: CGSize(width: 640, height: 300))
        let node = r.root.descendants(where: { $0 is NavigationSplitViewNode }).first as! NavigationSplitViewNode
        #expect(node.sidebarFrame?.width == 144)
        // Hovering the divider shows the resize pointer; elsewhere nothing.
        r.pointerMoved(to: CGPoint(x: 144, y: 150))
        #expect(r.pointerStyle == .columnResize(directions: .all))
        r.pointerMoved(to: CGPoint(x: 60, y: 150))
        #expect(r.pointerStyle == nil)
        // A drag of +30 widens the sidebar to 174 (within 100…200); +100 is clamped at 200.
        r.pointerDown(at: CGPoint(x: 144, y: 150))
        r.pointerMoved(to: CGPoint(x: 174, y: 150))
        r.layout(in: CGSize(width: 640, height: 300))
        #expect(node.sidebarFrame?.width == 174 && r.probeFrames["cherry"]?.minX == 174 + (200 - 41.5) / 2, "\(node.sidebarFrame as Any) \(r.probeFrames["cherry"] as Any)")
        r.pointerMoved(to: CGPoint(x: 260, y: 150))
        r.pointerUp(at: CGPoint(x: 260, y: 150))
        r.layout(in: CGSize(width: 640, height: 300))
        #expect(node.sidebarFrame?.width == 200)
        // The content divider: the column grows by 20.
        r.pointerDown(at: CGPoint(x: 400.5, y: 150))
        r.pointerMoved(to: CGPoint(x: 420.5, y: 150))
        r.pointerUp(at: CGPoint(x: 420.5, y: 150))
        r.layout(in: CGSize(width: 640, height: 300))
        #expect(node.contentFrame?.width == 220, "\(node.contentFrame as Any)")
        // Dragged under half the minimum (50), the sidebar collapses.
        r.pointerDown(at: CGPoint(x: 200, y: 150))
        r.pointerMoved(to: CGPoint(x: 30, y: 150))
        r.pointerUp(at: CGPoint(x: 30, y: 150))
        r.layout(in: CGSize(width: 640, height: 300))
        #expect(model.visibility == .detailOnly && node.sidebarFrame == nil)
        // A host painting window chrome gets the sidebar toggle leading the bar.
        r.paintsWindowChrome = true
        r.layout(in: CGSize(width: 640, height: 300))
        let toggle = r.semanticsTree().first { $0.label == "Toggle Sidebar" }
        #expect(toggle?.frame.minX == 8 && r.toolbarFrame?.height == 52, "\(toggle as Any)")
        if let toggle {
            r.activate(semanticsIdentifier: toggle.identifier)
            r.layout(in: CGSize(width: 640, height: 300))
            #expect(model.visibility == .all && node.sidebarFrame?.width == 144)
        }
    }

    /// sw-splitview: a compact width (the iOS profile) shows one column — the preferred compact
    /// column — and a link in the sidebar shows the detail, whose back returns to the sidebar.
    @Test func compactColumns() {
        @MainActor final class Column { var column = NavigationSplitViewColumn.sidebar }
        let box = Column()
        let r = Runtime()
        r.hostPlatformProfile = .iOS
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let ios17 = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body)
        for (word, width) in [("Go", 20.0), ("Pushed", 54.0), ("Detail", 46.0), ("Menu", 42.0)] {
            entries[RecordedTextEngine.key(font: ios17, width: nil, string: word)] = .init(width: width, height: 22, firstBaseline: 17, lastBaseline: 17)
        }
        r.textEngine = RecordedTextEngine(entries: entries)
        r.mount(NavigationSplitView(preferredCompactColumn: Binding(get: { box.column }, set: { box.column = $0 })) {
            VStack { Text("Menu")._probe("menu"); NavigationLink("Go") { Text("Pushed")._probe("pushed") }._probe("link") }._probe("sidebar")
        } detail: {
            Text("Detail")._probe("detail")
        }._probe("split"))
        r.layout(in: CGSize(width: 320, height: 480))
        // The sidebar fills the width; the detail is not shown.
        #expect(r.probeFrames["sidebar"]?.midX == 160 && r.probeFrames["detail"] == nil, "\(r.probeFrames)")
        let link = r.probeFrames["link"]!
        r.pointerDown(at: CGPoint(x: link.midX, y: link.midY)); r.pointerUp(at: CGPoint(x: link.midX, y: link.midY))
        r.layout(in: CGSize(width: 320, height: 480))
        r.layout(in: CGSize(width: 320, height: 480))
        #expect(box.column == .detail && r.probeFrames["pushed"] != nil && r.probeFrames["menu"] == nil, "\(r.probeFrames)")
        // Back pops the detail's stack and the sidebar returns.
        #expect(r.navigateBack())
        r.layout(in: CGSize(width: 320, height: 480))
        r.layout(in: CGSize(width: 320, height: 480))
        #expect(box.column == .sidebar && r.probeFrames["menu"] != nil && r.probeFrames["pushed"] == nil, "\(r.probeFrames)")
    }
}
#endif
