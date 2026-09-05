// Phase 6: gestures — drag, long press (ticking on the animation clock), tap counts, composition,
// @GestureState, and priority over subviews.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Log { var events: [String] = [] }

@Suite @MainActor struct GestureTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    // A 40 × 20 box centred in 200 × 100: x 80…120, y 40…60.
    private func press(_ runtime: Runtime, from start: CGPoint, through points: [CGPoint] = [], to end: CGPoint, times: [Double]? = nil) {
        var t = 0.0
        runtime.pointerDown(at: start, time: t)
        for point in points { t += 0.05; runtime.pointerMoved(to: point, time: t) }
        t += 0.05
        runtime.pointerUp(at: end, time: times?.last ?? t)
    }

    @Test func dragReportsTranslationAfterTheMinimumDistance() {
        let log = Log()
        let runtime = runtime(Color.red.frame(width: 40, height: 20).gesture(
            DragGesture().onChanged { log.events.append("changed \(Int($0.translation.width)),\(Int($0.translation.height)) at \(Int($0.location.x)),\(Int($0.location.y))") }
                .onEnded { log.events.append("ended \(Int($0.translation.width)) v\(Int($0.velocity.width.rounded()))") }))
        press(runtime, from: CGPoint(x: 90, y: 50), through: [CGPoint(x: 95, y: 50), CGPoint(x: 110, y: 52), CGPoint(x: 130, y: 55)], to: CGPoint(x: 130, y: 55))
        // The 5 pt move is below the 10 pt minimum; then local translations from the start.
        #expect(log.events == ["changed 20,2 at 30,12", "changed 40,5 at 50,15", "ended 40 v400"])
        // A release without reaching the minimum ends nothing; global spaces report window points.
        log.events.removeAll()
        press(runtime, from: CGPoint(x: 90, y: 50), through: [CGPoint(x: 93, y: 50)], to: CGPoint(x: 93, y: 50))
        #expect(log.events.isEmpty)
        let global = Log()
        let g = self.runtime(Color.red.frame(width: 40, height: 20).gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { global.events.append("\(Int($0.startLocation.x)),\(Int($0.startLocation.y))→\(Int($0.location.x))") }))
        press(g, from: CGPoint(x: 90, y: 50), through: [CGPoint(x: 100, y: 50)], to: CGPoint(x: 100, y: 50))
        #expect(global.events == ["90,50→100"])
    }

    @Test func longPressTicksOnTheAnimationClockAndCancelsOnMovement() {
        let log = Log()
        let runtime = runtime(Color.red.frame(width: 40, height: 20).onLongPressGesture(minimumDuration: 0.5) { log.events.append("pressed") } onPressingChanged: { log.events.append($0 ? "down" : "up") })
        runtime.pointerDown(at: CGPoint(x: 100, y: 50), time: 1)
        #expect(log.events == ["down"])
        #expect(runtime.advanceAnimations(elapsed: 0.2))
        #expect(log.events == ["down"])
        runtime.advanceAnimations(elapsed: 0.4)
        #expect(log.events == ["down", "pressed"])
        runtime.pointerUp(at: CGPoint(x: 100, y: 50), time: 2)
        #expect(log.events == ["down", "pressed", "up"])
        // Moving too far before the duration cancels; a short press never fires.
        log.events.removeAll()
        runtime.pointerDown(at: CGPoint(x: 100, y: 50), time: 3)
        runtime.pointerMoved(to: CGPoint(x: 130, y: 50), time: 3.1)
        runtime.advanceAnimations(elapsed: 1)
        runtime.pointerUp(at: CGPoint(x: 130, y: 50), time: 3.2)
        #expect(log.events == ["down", "up"])
        log.events.removeAll()
        runtime.pointerDown(at: CGPoint(x: 100, y: 50), time: 4)
        runtime.pointerUp(at: CGPoint(x: 100, y: 50), time: 4.1)
        #expect(log.events == ["down", "up"])
    }

    @Test func tapCountsAndGestureStateUpdating() {
        let log = Log()
        let runtime = runtime(Color.red.frame(width: 40, height: 20).gesture(TapGesture(count: 2).onEnded { log.events.append("double") }))
        let p = CGPoint(x: 100, y: 50)
        runtime.pointerDown(at: p, time: 0); runtime.pointerUp(at: p, time: 0.05)
        #expect(log.events.isEmpty)
        runtime.pointerDown(at: p, time: 0.2); runtime.pointerUp(at: p, time: 0.25)
        #expect(log.events == ["double"])
        // Two taps too far apart do not count.
        runtime.pointerDown(at: p, time: 1); runtime.pointerUp(at: p, time: 1.05)
        runtime.pointerDown(at: p, time: 2); runtime.pointerUp(at: p, time: 2.05)
        #expect(log.events == ["double"])
        // onTapGesture(count:) counts too.
        let modifier = self.runtime(Color.red.frame(width: 40, height: 20).onTapGesture(count: 2) { log.events.append("modifier") })
        modifier.pointerDown(at: p, time: 5); modifier.pointerUp(at: p, time: 5.05)
        #expect(!log.events.contains("modifier"))
        modifier.pointerDown(at: p, time: 5.2); modifier.pointerUp(at: p, time: 5.25)
        #expect(log.events.last == "modifier")
        // @GestureState follows the gesture and resets when it ends.
        struct Held: View {
            @GestureState var held = false
            let log: Log
            var body: some View {
                Text(held ? "Held" : "Idle")._probe(held ? "held" : "idle").frame(width: 40, height: 20)
                    .gesture(LongPressGesture(minimumDuration: 0.1).updating($held) { value, state, _ in state = value })
            }
        }
        let held = self.runtime(Held(log: log))
        #expect(held.probeFrames["idle"] != nil)
        held.pointerDown(at: p, time: 0)
        held.layout(in: CGSize(width: 200, height: 100))
        #expect(held.probeFrames["held"] != nil)
        held.advanceAnimations(elapsed: 0.2)
        held.pointerUp(at: p, time: 0.3)
        held.layout(in: CGSize(width: 200, height: 100))
        #expect(held.probeFrames["idle"] != nil)
    }

    @Test func sequencedSimultaneousAndExclusive() {
        let log = Log()
        let sequence = LongPressGesture(minimumDuration: 0.1).sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first: log.events.append("pressing")
                case .second(_, let drag): log.events.append(drag.map { "drag \(Int($0.translation.width))" } ?? "ready")
                }
            }
            .onEnded { _ in log.events.append("done") }
        let runtime = runtime(Color.red.frame(width: 40, height: 20).gesture(sequence))
        runtime.pointerDown(at: CGPoint(x: 90, y: 50), time: 0)
        runtime.advanceAnimations(elapsed: 0.2)
        runtime.pointerMoved(to: CGPoint(x: 100, y: 50), time: 0.3)
        runtime.pointerUp(at: CGPoint(x: 110, y: 50), time: 0.4)
        #expect(log.events == ["pressing", "ready", "drag 10", "done"])
        // Simultaneous: both values arrive; exclusive: the first to activate wins.
        let both = Log()
        let sim = self.runtime(Color.red.frame(width: 40, height: 20).gesture(
            DragGesture(minimumDistance: 0).simultaneously(with: TapGesture()).onEnded { both.events.append("drag \($0.first != nil) tap \($0.second != nil)") }))
        sim.pointerDown(at: CGPoint(x: 90, y: 50), time: 0); sim.pointerMoved(to: CGPoint(x: 92, y: 50), time: 0.1); sim.pointerUp(at: CGPoint(x: 92, y: 50), time: 0.2)
        #expect(both.events.contains("drag true tap false") && both.events.contains("drag true tap true"))
        let ex = Log()
        let exclusive = self.runtime(Color.red.frame(width: 40, height: 20).gesture(
            DragGesture(minimumDistance: 0).exclusively(before: LongPressGesture(minimumDuration: 0.1)).onEnded { value in
                if case .first = value { ex.events.append("drag") } else { ex.events.append("press") }
            }))
        exclusive.pointerDown(at: CGPoint(x: 90, y: 50), time: 0); exclusive.pointerMoved(to: CGPoint(x: 95, y: 50), time: 0.1)
        exclusive.advanceAnimations(elapsed: 1)
        exclusive.pointerUp(at: CGPoint(x: 95, y: 50), time: 0.2)
        #expect(ex.events == ["drag"])
    }

    @Test func highPriorityGestureBeatsAnInnerButton() {
        let log = Log()
        let inner = self.runtime(Button("Tap") { log.events.append("button") }.gesture(TapGesture().onEnded { log.events.append("gesture") }))
        let p = CGPoint(x: 100, y: 50)
        inner.pointerDown(at: p, time: 0); inner.pointerUp(at: p, time: 0.1)
        #expect(log.events == ["button"])
        log.events.removeAll()
        let high = self.runtime(Button("Tap") { log.events.append("button") }.highPriorityGesture(TapGesture().onEnded { log.events.append("gesture") }))
        high.pointerDown(at: p, time: 0); high.pointerUp(at: p, time: 0.1)
        #expect(log.events == ["gesture"])
        // Gesture nodes expose their children rather than themselves.
        #expect(high.semanticsTree().contains { $0.label == "Tap" })
    }
}
#endif
