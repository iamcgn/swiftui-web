// Phase 1 step 11: Button, button styles, hit testing, semantics.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Counter { var taps = 0; var pressed: [Bool] = [] }

private struct Tracking: ButtonStyle {
    let counter: Counter
    func makeBody(configuration: Configuration) -> some View {
        let _ = counter.pressed.append(configuration.isPressed)
        return configuration.label.padding(2)
    }
}

@MainActor private func engine() -> RecordedTextEngine {
    let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    let label = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    var entries: [String: RecordedTextEngine.Entry] = [:]
    for (font, h, base) in [(body, 18.5, 14.0), (label, 16.0, 13.0)] {
        entries[RecordedTextEngine.key(font: font, width: nil, string: "OK")] = .init(width: 18.5, height: h, firstBaseline: base, lastBaseline: base)
        entries[RecordedTextEngine.key(font: font, width: nil, string: "Go")] = .init(width: 18.5, height: h, firstBaseline: base, lastBaseline: base)
    }
    return RecordedTextEngine(entries: entries)
}

@Suite @MainActor struct ButtonTests {
    @Test func tapActivatesOnlyWhenReleasedInside() {
        let counter = Counter()
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: engine())
        renderer.mount(Button("OK") { counter.taps += 1 }._probe("button"))
        renderer.renderFrame()
        let frame = renderer.probeFrames["button"]!
        #expect(frame.size == CGSize(width: 42.5, height: 24))
        let inside = CGPoint(x: frame.midX, y: frame.midY)

        renderer.runtime.pointerDown(at: inside)
        renderer.runtime.pointerUp(at: inside)
        #expect(counter.taps == 1)

        renderer.runtime.pointerDown(at: inside)
        renderer.runtime.pointerUp(at: CGPoint(x: 1, y: 1))     // released outside: no action
        #expect(counter.taps == 1)

        renderer.runtime.pointerDown(at: CGPoint(x: 1, y: 1))   // pressed outside: nothing
        renderer.runtime.pointerUp(at: inside)
        #expect(counter.taps == 1)
    }

    @Test func pressStateReachesTheStyle() {
        let counter = Counter()
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: engine())
        renderer.mount(Button("OK") {}.buttonStyle(Tracking(counter: counter))._probe("button"))
        renderer.renderFrame()
        #expect(counter.pressed == [false])
        #expect(renderer.probeFrames["button"]?.size == CGSize(width: 22.5, height: 20))   // 16 pt label + 2 pt padding
        let inside = CGPoint(x: 100, y: 50)
        renderer.runtime.pointerDown(at: inside)
        renderer.renderFrame()
        #expect(counter.pressed == [false, true])
        renderer.runtime.pointerUp(at: inside)
        renderer.renderFrame()
        #expect(counter.pressed == [false, true, false])
    }

    @Test func stylesPaintTheirGeometry() {
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: engine())
        renderer.mount(Button("OK") {})
        let list = renderer.renderFrame().commands.map(\.description)
        #expect(list == [
            "fillRRect(79, 38, 42.5, 24) r=6 #000000@0.07450980392156863",
            "drawText(\"OK\" system 13 w400 at 91,55 #000000@0.85)",
        ])
        renderer.mount(Button("OK") {}.buttonStyle(.borderedProminent))
        #expect(renderer.renderFrame().commands.map(\.description) == [
            "fillRRect(79, 38, 42.5, 24) r=6 #0088FF",
            "drawText(\"OK\" system 13 w400 at 91,55 #FFFFFF)",
        ])
        renderer.mount(Button("OK") {}.buttonStyle(.plain))
        #expect(renderer.renderFrame().commands.map(\.description) == [
            "drawText(\"OK\" system 13 w400 at 91,55 #000000@0.85)",
        ])
    }

    @Test func topmostInteractiveNodeWins() {
        let counter = Counter()
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: engine())
        renderer.mount(ZStack {
            Color.red.frame(width: 100, height: 100).onTapGesture { counter.taps += 10 }
            Button("Go") { counter.taps += 1 }
        })
        renderer.renderFrame()
        renderer.runtime.pointerDown(at: CGPoint(x: 100, y: 50))
        renderer.runtime.pointerUp(at: CGPoint(x: 100, y: 50))
        #expect(counter.taps == 1)
        renderer.runtime.pointerDown(at: CGPoint(x: 55, y: 5))
        renderer.runtime.pointerUp(at: CGPoint(x: 55, y: 5))
        #expect(counter.taps == 11)
    }

    @Test func semanticsTreeListsButtons() {
        let counter = Counter()
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: engine())
        renderer.mount(HStack { Button("OK") { counter.taps += 1 }; Button("Go") { counter.taps += 100 } })
        renderer.renderFrame()
        let tree = renderer.runtime.semanticsTree()
        #expect(tree.map(\.label) == ["OK", "Go"])
        #expect(tree.map(\.role) == [.button, .button])
        #expect(tree[0].frame.width == 42.5)
        renderer.runtime.activate(semanticsIdentifier: tree[1].identifier)
        #expect(counter.taps == 100)
    }
}
#endif
