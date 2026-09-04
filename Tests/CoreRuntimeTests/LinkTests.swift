// Link: the link colour, the disabled look, the environment's font, and opening through the
// openURL action (custom handlers and the host's opener). Layout against goldens is in
// GoldenFrameTests.
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct LinkTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Apple"): .init(width: 35, height: 16, firstBaseline: 13, lastBaseline: 13),
        ])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func looks() {
        let url = URL(string: "https://www.apple.com")!
        let r = runtime(Link("Apple", destination: url)._probe("link"))
        #expect(r.probeFrames["link"] == CGRect(x: 82.5, y: 42, width: 35, height: 16))
        // The fixed link blue (0, 104, 218), half opacity when disabled.
        #expect(r.render(scale: 2).commands.map(\.description) == ["drawText(\"Apple\" system 13 w400 at 82.5,55 #0068DA)"])
        let disabled = runtime(Link("Apple", destination: url).disabled(true))
        #expect(disabled.render(scale: 2).commands.map(\.description).first?.hasSuffix("#0068DA@0.5)") == true)
    }

    @Test func opensThroughTheEnvironment() {
        let url = URL(string: "https://www.apple.com")!
        let box = _URLBox()
        OpenURLAction.systemHandler = { box.system.append($0) }
        defer { OpenURLAction.systemHandler = nil }
        let r = runtime(Link("Apple", destination: url)._probe("link"))
        let link = r.probeFrames["link"]!
        r.pointerDown(at: CGPoint(x: link.midX, y: link.midY)); r.pointerUp(at: CGPoint(x: link.midX, y: link.midY))
        #expect(box.system == [url])
        // A custom action can handle, discard or redirect to the system.
        let custom = runtime(Link("Apple", destination: url)._probe("link").environment(\.openURL, OpenURLAction { box.custom.append($0); return .handled }))
        let frame = custom.probeFrames["link"]!
        custom.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY)); custom.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(box.custom == [url] && box.system == [url])
        let other = URL(string: "https://example.com")!
        let redirect = runtime(Link("Apple", destination: url)._probe("link").environment(\.openURL, OpenURLAction { _ in .systemAction(other) }))
        let f2 = redirect.probeFrames["link"]!
        redirect.pointerDown(at: CGPoint(x: f2.midX, y: f2.midY)); redirect.pointerUp(at: CGPoint(x: f2.midX, y: f2.midY))
        #expect(box.system == [url, other])
        // Nothing opens while disabled.
        let disabled = runtime(Link("Apple", destination: url).disabled(true)._probe("link"))
        let f3 = disabled.probeFrames["link"]!
        disabled.pointerDown(at: CGPoint(x: f3.midX, y: f3.midY)); disabled.pointerUp(at: CGPoint(x: f3.midX, y: f3.midY))
        #expect(box.system.count == 2)
    }
}

private final class _URLBox: @unchecked Sendable {
    var system: [URL] = []
    var custom: [URL] = []
}
#endif
