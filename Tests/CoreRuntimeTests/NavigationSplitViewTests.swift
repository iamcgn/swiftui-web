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
        // The sidebar panel is inset 8 on every side of its 148 pt column; the detail starts at
        // the panel's trailing edge with its content centred.
        #expect(r.probeFrames["split"] == CGRect(x: 0, y: 0, width: 480, height: 300))
        #expect(r.probeFrames["sidebar"] == CGRect(x: 8, y: 8, width: 140, height: 284))
        #expect(r.probeFrames["row1"] == CGRect(x: 24, y: 24.75, width: 35, height: 18.5))
        #expect(r.probeFrames["detail"] == CGRect(x: 296.5, y: 142, width: 35, height: 16))
        let node = r.root.descendants(where: { $0 is NavigationSplitViewNode }).first as! NavigationSplitViewNode
        #expect(node.detailFrame == CGRect(x: 148, y: 0, width: 332, height: 300))
        let painted = commands(r)
        #expect(painted.contains { $0.hasPrefix("fillRRect(8, 8, 140, 284) r=7.5") })
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
        // Non-list sidebar content is centred in the panel; the content column is a full-height
        // column at the panel's edge, then a 1 pt divider, then the detail.
        #expect(r.probeFrames["sidebar"] == CGRect(x: 8 + (120 - 34) / 2, y: 142, width: 34, height: 16))
        #expect(r.probeFrames["content"] == CGRect(x: 128, y: 0, width: 160, height: 300))
        #expect(r.probeFrames["cherry"] == CGRect(x: 144, y: 14, width: 41.5, height: 16))
        #expect(r.probeFrames["detail"]?.midX == 464.5)
        #expect(commands(r).contains { $0.hasPrefix("fillRect(288, 0, 1, 300)") })
        // Without a width the content column is 200 wide.
        let plain = runtime(NavigationSplitView {
            Text("Menu")
        } content: {
            Text("Cherry")._probe("cherry")
        } detail: {
            Text("Detail")._probe("detail")
        }, size: CGSize(width: 640, height: 300))
        #expect(plain.probeFrames["cherry"]?.midX == 248.0)
        #expect(plain.probeFrames["detail"]?.midX == 494.5)
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
        #expect(r.probeFrames["menu"]?.midX == 78 && r.probeFrames["detail"]?.midX == 314)
        // The toggle and ⌃⌘S go through the binding.
        #expect(r.toggleSidebar() && model.visibility == .detailOnly)
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["detail"]?.midX == 240)
        #expect(r.keyDown(KeyEvent(key: KeyEquivalent("s"), modifiers: [.control, .command])) && model.visibility == .all)
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["detail"]?.midX == 314)
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
        #expect(r.probeFrames["pushed"]?.midX == 314)
        #expect(r.navigateBack())
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["pushed"] == nil && r.probeFrames["detail"]?.midX == 314)
        let valueLink = r.probeFrames["valueLink"]!
        r.pointerDown(at: CGPoint(x: valueLink.midX, y: valueLink.midY)); r.pointerUp(at: CGPoint(x: valueLink.midX, y: valueLink.midY))
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["number"]?.midX == 314)
        #expect(r.navigateBack())
        r.layout(in: CGSize(width: 480, height: 300))
        #expect(r.probeFrames["number"] == nil)
    }
}
#endif
