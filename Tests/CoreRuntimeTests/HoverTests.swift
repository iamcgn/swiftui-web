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

    /// sw-hover-looks: `hoverEffect` on the iOS profile paints the highlight (a translucent
    /// rounded rect under the view, the content scaled) or the lift (a shadow and a larger
    /// scale) while hovered, easing over 0.2 s; disabled effects and macOS views paint nothing.
    @Test func hoverEffectsOnTheIOSProfile() {
        func make(_ view: some View, profile: PlatformProfile = .iOS) -> Runtime {
            let r = Runtime()
            r.hostPlatformProfile = profile
            r.textEngine = RecordedTextEngine(entries: [:])
            r.mount(view)
            r.layout(in: CGSize(width: 200, height: 100))
            return r
        }
        func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
        let highlight = make(Color.blue.frame(width: 60, height: 30).hoverEffect().position(x: 100, y: 50))
        #expect(!commands(highlight).contains { $0.hasPrefix("fillRRect") || $0.hasPrefix("concat") })
        highlight.pointerMoved(to: CGPoint(x: 100, y: 50))
        // Half way through the ease the tint is between; settled, the pad is 4 and the alpha 0.1.
        highlight.advanceAnimations(elapsed: 0.1)
        let midway = commands(highlight).first { $0.hasPrefix("fillRRect") }
        #expect(midway?.hasPrefix("fillRRect(66, 31, 68, 38) r=8") == true, "\(midway as Any)")
        highlight.advanceAnimations(elapsed: 0.2)
        let settled = commands(highlight)
        #expect(settled.contains { $0.hasPrefix("fillRRect(66, 31, 68, 38) r=8") && $0.hasSuffix("#000000@0.1") }, "\(settled)")
        #expect(settled.contains { $0.hasPrefix("concat(") }, "\(settled)")
        // Leaving eases back out and ends with nothing painted.
        highlight.pointerMoved(to: CGPoint(x: 10, y: 10))
        highlight.advanceAnimations(elapsed: 0.3)
        #expect(!commands(highlight).contains { $0.hasPrefix("fillRRect") })
        // The lift: a shadow group and the 1.15 scale, no tint.
        let lift = make(Color.blue.frame(width: 60, height: 30).hoverEffect(.lift).position(x: 100, y: 50))
        lift.pointerMoved(to: CGPoint(x: 100, y: 50))
        lift.advanceAnimations(elapsed: 0.3)
        let lifted = commands(lift)
        #expect(lifted.contains { $0.hasPrefix("beginShadow(#000000@0.2 r=12 dx=0 dy=8") } && !lifted.contains { $0.hasPrefix("fillRRect") }, "\(lifted)")
        #expect(lifted.contains { $0.hasPrefix("concat(") && $0.contains("1.15") }, "\(lifted)")
        // hoverEffectDisabled, a disabled effect, and macOS: nothing.
        for view in [AnyView(Color.blue.frame(width: 60, height: 30).hoverEffect().hoverEffectDisabled().position(x: 100, y: 50)),
                     AnyView(Color.blue.frame(width: 60, height: 30).hoverEffect(.lift, isEnabled: false).position(x: 100, y: 50))] {
            let r = make(view)
            r.pointerMoved(to: CGPoint(x: 100, y: 50))
            r.advanceAnimations(elapsed: 0.3)
            #expect(!commands(r).contains { $0.hasPrefix("fillRRect") || $0.hasPrefix("beginShadow") })
        }
        let mac = make(Color.blue.frame(width: 60, height: 30).hoverEffect().position(x: 100, y: 50), profile: .macOS)
        mac.pointerMoved(to: CGPoint(x: 100, y: 50))
        mac.advanceAnimations(elapsed: 0.3)
        #expect(!commands(mac).contains { $0.hasPrefix("fillRRect") || $0.hasPrefix("concat") })
        // The default effect fills in for `.automatic`.
        let defaulted = make(Color.blue.frame(width: 60, height: 30).hoverEffect().position(x: 100, y: 50).defaultHoverEffect(.lift))
        defaulted.pointerMoved(to: CGPoint(x: 100, y: 50))
        defaulted.advanceAnimations(elapsed: 0.3)
        #expect(commands(defaulted).contains { $0.hasPrefix("beginShadow") })
    }
}
#endif
