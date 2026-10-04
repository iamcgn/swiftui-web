// TabView (bar geometry, selection by press and keys, own state), ContentUnavailableView (the
// title/description/actions column) and ShareLink (the share button and the host handler).
// Layout against goldens is in GoldenFrameTests.
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct TabViewTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("One", 25.0), ("Two", 25.0), ("Three", 35.5), ("First", 27.0), ("Second", 46.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 360, height: 260))
        return runtime
    }

    @Observable final class Model: @unchecked Sendable { var selection = 0 }

    @Test func barAndContent() {
        let model = Model()
        let r = runtime(TabView(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            Text("First")._probe("first").tabItem { Text("One") }.tag(0)
            Text("Second")._probe("second").tabItem { Text("Two") }.tag(1)
            Color.red.tabItem { Text("Three") }.tag(2)
        }._probe("tabs"))
        // The tab view fills its space; the bar is the segments (title + 24, 1 between) centred.
        #expect(r.probeFrames["tabs"] == CGRect(x: 0, y: 0, width: 360, height: 260))
        let node = r.root.descendants(where: { $0 is TabViewNode }).first as! TabViewNode
        #expect(node.bar == CGRect(x: 100, y: 0, width: 160, height: 24))
        #expect(node.tabs.map(\.segment.width) == [49, 49, 59.5])
        // The selected content is centred in the area under the bar; others are not laid out.
        #expect(r.probeFrames["first"] == CGRect(x: 166.5, y: 134, width: 27, height: 16))
        #expect(r.probeFrames["second"] == nil)
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("fillRRect(0, 10, 360, 250) r=4.5") })
        #expect(commands.contains { $0.hasPrefix("fillRRect(100.5, 0.5, 48, 23) r=5.5") })
        #expect(commands.filter { $0.hasPrefix("drawText") }.count == 4)
        // A press on a segment selects its tab; arrow keys move it.
        r.pointerDown(at: CGPoint(x: 170, y: 12)); r.pointerUp(at: CGPoint(x: 170, y: 12))
        #expect(model.selection == 1)
        r.layout(in: CGSize(width: 360, height: 260))
        #expect(r.probeFrames["first"] == nil && r.probeFrames["second"]?.width == 46)
        let bar = r.semanticsTree().first { $0.role == .segmented }!
        #expect(bar.value == "Two")
        r.focus(semanticsIdentifier: bar.identifier)
        #expect(r.keyDown(KeyEvent(key: .rightArrow)) && model.selection == 2)
        r.layout(in: CGSize(width: 360, height: 260))
        #expect(r.keyDown(KeyEvent(key: .leftArrow)) && model.selection == 1)
    }

    @Test func ownSelection() {
        let r = runtime(TabView {
            Text("First")._probe("first").tabItem { Text("One") }
            Text("Second")._probe("second").tabItem { Text("Two") }
        })
        #expect(r.probeFrames["first"] != nil && r.probeFrames["second"] == nil)
        r.pointerDown(at: CGPoint(x: 200, y: 12)); r.pointerUp(at: CGPoint(x: 200, y: 12))
        r.layout(in: CGSize(width: 360, height: 260))
        #expect(r.probeFrames["second"] != nil && r.probeFrames["first"] == nil)
    }
}

@Suite @MainActor struct UnavailableAndShareTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    static let large = ResolvedFont(family: "system", size: 26, weight: .bold, italic: false, textStyle: .largeTitle, weightOverridden: true)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        entries[RecordedTextEngine.key(font: Self.large, width: nil, string: "No Mail")] = .init(width: 90, height: 38, firstBaseline: 29, lastBaseline: 29)
        entries[RecordedTextEngine.key(font: Self.body, width: nil, string: "Try again.")] = .init(width: 60, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        for (word, width) in [("Share…", 45.5), ("Retry", 32.5)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 300, height: 200))
        return runtime
    }

    @Test func unavailableColumn() {
        let r = runtime(ContentUnavailableView { Label("No Mail", systemImage: "tray")._probe("label") } description: { Text("Try again.")._probe("description") } actions: { Button("Retry") {}._probe("action") }._probe("view"))
        // Fills the space; the column starts 20 down: title (large bold, title only), 12, description, 12, actions.
        #expect(r.probeFrames["view"] == CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(r.probeFrames["label"] == CGRect(x: 105, y: 20, width: 90, height: 38))
        #expect(r.probeFrames["description"] == CGRect(x: 120, y: 70, width: 60, height: 18.5))
        #expect(r.probeFrames["action"]?.minY == 100.5)
        let commands = r.render(scale: 2).commands.map(\.description)
        // Secondary colour on the title and description, and no icon for the label.
        #expect(commands.contains { $0.hasPrefix("drawText(\"No Mail\" system 26 w700") && $0.hasSuffix("#000000@0.5)") })
        #expect(!commands.contains { $0.hasPrefix("strokePath") && !$0.contains("w=1") })
        #expect(ContentUnavailableView.search.description?.resolvedString == "Check the spelling or try a new search.")
    }

    @Test func shareLink() {
        let box = _ShareBox()
        ShareAction.systemHandler = { items, subject in box.items = items; box.subject = subject }
        defer { ShareAction.systemHandler = nil }
        let r = runtime(ShareLink(item: URL(string: "https://www.apple.com")!, subject: Text("Retry"))._probe("share"))
        // A bordered button: 12 + the symbol (14.5) + 8 + "Share…" + 12, the symbol's 17.5 + 8 tall.
        #expect(abs((r.probeFrames["share"]?.width ?? 0) - 92) < 1e-9)
        // The label centres its icon on the cap height, which leaves it 17.58 tall (25.58 with the button's 8), as Apple's.
        #expect(abs((r.probeFrames["share"]?.height ?? 0) - 25.5798) < 0.01)
        let share = r.probeFrames["share"]!
        r.pointerDown(at: CGPoint(x: share.midX, y: share.midY)); r.pointerUp(at: CGPoint(x: share.midX, y: share.midY))
        #expect(box.items == ["https://www.apple.com"] && box.subject == "Retry")
    }
}

private final class _ShareBox: @unchecked Sendable {
    var items: [String] = []
    var subject: String?
}
#endif

// MARK: - Phase 8 step 6, sw-tabview

@Observable
private final class TabAPIModel {
    var selection = 0
}

private struct TabAPIView: View {
    let model: TabAPIModel
    var body: some View {
        TabView(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            Tab("Home", systemImage: "house", value: 0) { Text("Home content")._probe("home") }
            Tab("Alerts", systemImage: "bell", value: 1) { Text("Alerts content")._probe("alerts") }.badge(3)
            Tab("Off", systemImage: "gear", value: 2) { Text("Off content")._probe("off") }.disabled(true)
        }
        ._probe("tabs")
    }
}

private struct PagedView: View {
    let model: TabAPIModel
    var body: some View {
        TabView(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            Color.red.frame(width: 80, height: 50)._probe("page0").tag(0)
            Color.blue.frame(width: 80, height: 50)._probe("page1").tag(1)
            Color.green.frame(width: 80, height: 50)._probe("page2").tag(2)
        }
        .tabViewStyle(.page)
        .frame(width: 240, height: 160)
        ._probe("tabs")
    }
}

@Suite @MainActor struct TabAPITests {
    private let size = CGSize(width: 360, height: 260)

    @Test func tabsCarryTitlesBadgesAndDisabledState() {
        let model = TabAPIModel()
        let runtime = Runtime()
        runtime.mount(TabAPIView(model: model))
        runtime.layout(in: size)
        let node = runtime.root.descendants(where: { $0 is TabViewNode }).first as! TabViewNode
        #expect(node.tabs.map(\.title) == ["Home", "Alerts", "Off"])
        #expect(node.tabs.map(\.symbol) == ["house", "bell", "gear"])
        #expect(node.tabs.map(\.badge) == [nil, "3", nil])
        #expect(node.tabs.map(\.isEnabled) == [true, true, false])
        #expect(runtime.probeFrames["home"] != nil && runtime.probeFrames["alerts"] == nil)
        // A press on the disabled segment does nothing; on the second it selects.
        let off = node.tabs[2].segment, alerts = node.tabs[1].segment
        let origin = runtime.probeFrames["tabs"]!.origin
        runtime.pointerDown(at: CGPoint(x: origin.x + off.midX, y: origin.y + off.midY))
        runtime.pointerUp(at: CGPoint(x: origin.x + off.midX, y: origin.y + off.midY))
        #expect(model.selection == 0)
        runtime.pointerDown(at: CGPoint(x: origin.x + alerts.midX, y: origin.y + alerts.midY))
        runtime.pointerUp(at: CGPoint(x: origin.x + alerts.midX, y: origin.y + alerts.midY))
        runtime.layout(in: size)
        #expect(model.selection == 1 && runtime.probeFrames["alerts"] != nil)
        // Arrow keys skip the disabled tab.
        runtime.layout(in: size)
        #expect(node.handleKey(KeyPress(phase: .down, key: .rightArrow, characters: "", modifiers: [])))
        #expect(model.selection == 1)
        #expect(node.handleKey(KeyPress(phase: .down, key: .leftArrow, characters: "", modifiers: [])))
        #expect(model.selection == 0)
    }

    @Test func badgeModifiersResolveTheirText() {
        func text<V: View>(_ view: V) -> String? {
            let runtime = Runtime()
            runtime.mount(view)
            runtime.layout(in: size)
            return (runtime.root.descendants(where: { $0 is any _TabBadgeProviding }).first as? any _TabBadgeProviding)?.badgeText
        }
        #expect(text(Text("a").badge(5)) == "5")
        #expect(text(Text("a").badge(0)) == nil)
        #expect(text(Text("a").badge("New")) == "New")
        #expect(text(Text("a").badge(Text("Late"))) == "Late")
        #expect(text(Text("a").badge(nil as Text?)) == nil)
    }

    @Test func pageStyleLaysPagesSideBySideAndSwipes() {
        let model = TabAPIModel()
        let runtime = Runtime()
        runtime.mount(PagedView(model: model))
        runtime.layout(in: size)
        let tabs = runtime.probeFrames["tabs"]!
        #expect(tabs.size == CGSize(width: 240, height: 160))
        // The selected page is centred in the frame, the next one a frame's width to the right.
        #expect(runtime.probeFrames["page0"] == CGRect(x: tabs.minX + 80, y: tabs.minY + 55, width: 80, height: 50))
        #expect(runtime.probeFrames["page1"] == CGRect(x: tabs.minX + 320, y: tabs.minY + 55, width: 80, height: 50))
        model.selection = 2
        runtime.layout(in: size)
        #expect(runtime.probeFrames["page2"]?.minX == tabs.minX + 80 && runtime.probeFrames["page0"]?.minX == tabs.minX - 400)
        // A swipe to the right goes back a page; a short one does not.
        runtime.pointerDown(at: CGPoint(x: tabs.midX, y: tabs.midY))
        runtime.pointerMoved(to: CGPoint(x: tabs.midX + 60, y: tabs.midY))
        runtime.pointerUp(at: CGPoint(x: tabs.midX + 60, y: tabs.midY))
        runtime.layout(in: size)
        #expect(model.selection == 1)
        runtime.pointerDown(at: CGPoint(x: tabs.midX, y: tabs.midY))
        runtime.pointerUp(at: CGPoint(x: tabs.midX + 10, y: tabs.midY))
        #expect(model.selection == 1)
        // The indicator: three dots, the current one darker.
        let dots = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillPath") }
        #expect(dots.count == 3)
    }
}
