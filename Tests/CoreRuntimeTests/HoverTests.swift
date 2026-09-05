// Phase 6: hovering (`onHover`, `onContinuousHover`), `help` tooltips and `pointerStyle`.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class HoverLog {
    var events: [String] = []
}

@Suite @MainActor struct HoverTests {
    private static let tooltipFont = Font.system(size: 11).resolve(profile: EnvironmentValues().platformProfile)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Tip", 16.0), ("Low", 20.0)] {
            entries[RecordedTextEngine.key(font: Self.tooltipFont, width: nil, string: word)] = .init(width: width, height: 13, firstBaseline: 11, lastBaseline: 11)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func onHoverEntersOnceAndLeavesOnce() {
        let log = HoverLog()
        // A 40 × 20 box centred in 200 × 100: x 80…120, y 40…60.
        let runtime = runtime(Color.red.frame(width: 40, height: 20).onHover { log.events.append($0 ? "in" : "out") })
        runtime.pointerMoved(to: CGPoint(x: 10, y: 10))
        #expect(log.events.isEmpty)
        runtime.pointerMoved(to: CGPoint(x: 90, y: 50))
        runtime.pointerMoved(to: CGPoint(x: 95, y: 55))
        #expect(log.events == ["in"])
        runtime.pointerMoved(to: CGPoint(x: 150, y: 50))
        #expect(log.events == ["in", "out"])
        // Leaving the window ends a hover too.
        runtime.pointerMoved(to: CGPoint(x: 100, y: 50))
        runtime.pointerLeft()
        #expect(log.events == ["in", "out", "in", "out"])
    }

    @Test func continuousHoverReportsLocalOrGlobalPoints() {
        let log = HoverLog()
        let runtime = runtime(VStack(spacing: 0) {
            Color.red.frame(width: 40, height: 20).onContinuousHover { phase in
                if case .active(let p) = phase { log.events.append("local \(Int(p.x)),\(Int(p.y))") } else { log.events.append("ended") }
            }
            Color.blue.frame(width: 40, height: 20).onContinuousHover(coordinateSpace: .global) { phase in
                if case .active(let p) = phase { log.events.append("global \(Int(p.x)),\(Int(p.y))") }
            }
        })
        // Red spans y 30…50, blue 50…70, both x 80…120.
        runtime.pointerMoved(to: CGPoint(x: 90, y: 35))
        runtime.pointerMoved(to: CGPoint(x: 100, y: 45))
        runtime.pointerMoved(to: CGPoint(x: 100, y: 60))
        #expect(log.events == ["local 10,5", "local 20,15", "ended", "global 100,60"])
    }

    @Test func helpShowsATooltipAfterTheDelayAndHidesOnLeave() {
        let runtime = runtime(Color.red.frame(width: 40, height: 20).help("Tip"))
        #expect(runtime.visibleTooltip == nil)
        runtime.pointerMoved(to: CGPoint(x: 100, y: 50))
        // Pending: the host keeps frames coming, nothing shows yet.
        #expect(runtime.needsFrame && runtime.visibleTooltip == nil)
        #expect(runtime.advanceAnimations(elapsed: 0.5))
        #expect(runtime.visibleTooltip == nil)
        runtime.advanceAnimations(elapsed: 0.6)
        let tooltip = runtime.visibleTooltip
        #expect(tooltip?.text == "Tip")
        // Below and right of the pointer, and painted last.
        #expect(tooltip.map { $0.frame.minY == 70 && $0.frame.minX == 100 && $0.frame.width > 20 } == true)
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("drawText(\"Tip\"") } && commands.contains { $0.hasPrefix("fillRRect") })
        runtime.pointerMoved(to: CGPoint(x: 10, y: 10))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.visibleTooltip == nil && !runtime.needsFrame)
        // A tooltip near the bottom flips above the pointer.
        let low = self.runtime(VStack { Spacer(); Color.red.frame(width: 40, height: 20).help("Low") })
        low.pointerMoved(to: CGPoint(x: 100, y: 95))
        low.advanceAnimations(elapsed: 2)
        #expect(low.visibleTooltip.map { $0.frame.maxY <= 87 } == true)
    }

    @Test func pointerStyleFollowsTheDeepestHoveredView() {
        let runtime = runtime(HStack(spacing: 0) {
            Color.red.frame(width: 40, height: 20).pointerStyle(.link)
            Color.blue.frame(width: 40, height: 20).pointerStyle(.horizontalText).pointerStyle(.grabIdle)
            Color.green.frame(width: 40, height: 20)
        })
        #expect(runtime.pointerStyle == nil)
        runtime.pointerMoved(to: CGPoint(x: 50, y: 50))
        #expect(runtime.pointerStyle == .link)
        runtime.pointerMoved(to: CGPoint(x: 100, y: 50))
        #expect(runtime.pointerStyle == .horizontalText)
        runtime.pointerMoved(to: CGPoint(x: 140, y: 50))
        #expect(runtime.pointerStyle == nil)
        #expect(PointerStyle.columnResize(directions: .leading).css == "w-resize" && PointerStyle.frameResize(position: .topLeading).css == "nwse-resize")
    }
}
#endif
