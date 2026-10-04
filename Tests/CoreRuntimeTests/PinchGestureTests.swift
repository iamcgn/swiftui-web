// Phase 8 step 6, sw-gestures: pinches from the host (`Runtime.pinch`) reaching magnify and
// rotate gestures, their thresholds, velocities and anchors, the older gestures, the deepest
// target and `simultaneousGesture` ancestors; `simultaneousGesture` alongside a subview's
// control; gesture masks; `@GestureState` transactions and reset closures.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Log { var events: [String] = [] }

@Suite @MainActor struct PinchGestureTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    // A 40 × 20 box centred in 200 × 100: x 80…120, y 40…60.
    private let centre = CGPoint(x: 100, y: 50)

    private func f2(_ value: CGFloat) -> String { String(Int((value * 100).rounded())) }

    @Test func magnifyReportsScaleVelocityAndAnchor() {
        let log = Log()
        let runtime = runtime(Color.red.frame(width: 40, height: 20).gesture(
            MagnifyGesture()
                .onChanged { log.events.append("changed \(f2($0.magnification)) v\(f2($0.velocity)) a\(f2($0.startAnchor.x)),\(f2($0.startAnchor.y)) at \(Int($0.startLocation.x)),\(Int($0.startLocation.y))") }
                .onEnded { log.events.append("ended \(f2($0.magnification))") }))
        runtime.pinch(.began, scale: 1, rotation: 0, at: CGPoint(x: 90, y: 55), time: 0)
        // Below the minimum scale delta nothing is reported.
        runtime.pinch(.changed, scale: 1.005, rotation: 0, at: CGPoint(x: 90, y: 55), time: 0.1)
        #expect(log.events.isEmpty)
        runtime.pinch(.changed, scale: 1.205, rotation: 0, at: CGPoint(x: 90, y: 55), time: 0.2)
        #expect(log.events == ["changed 121 v200 a25,75 at 10,15"])
        runtime.pinch(.ended, scale: 1.5, rotation: 0, at: CGPoint(x: 90, y: 55), time: 0.3)
        #expect(log.events.last == "ended 150")
        // A cancelled pinch ends without a value; a pinch elsewhere reaches nothing.
        runtime.pinch(.began, scale: 1, rotation: 0, at: centre, time: 1)
        runtime.pinch(.changed, scale: 2, rotation: 0, at: centre, time: 1.1)
        runtime.pinch(.cancelled, scale: 2, rotation: 0, at: centre, time: 1.2)
        #expect(log.events.count == 3 && log.events.last == "changed 200 v1000 a50,50 at 20,10")
        runtime.pinch(.began, scale: 1, rotation: 0, at: CGPoint(x: 10, y: 10), time: 2)
        runtime.pinch(.changed, scale: 2, rotation: 0, at: CGPoint(x: 10, y: 10), time: 2.1)
        runtime.pinch(.ended, scale: 2, rotation: 0, at: CGPoint(x: 10, y: 10), time: 2.2)
        #expect(log.events.count == 3)
    }

    @Test func rotateAndTheOlderGestures() {
        let log = Log()
        let runtime = runtime(Color.red.frame(width: 40, height: 20).gesture(
            RotateGesture().onChanged { log.events.append("rotate \(Int($0.rotation.degrees.rounded())) v\(Int($0.velocity.degrees.rounded()))") }
                .onEnded { log.events.append("rotated \(Int($0.rotation.degrees.rounded()))") }))
        runtime.pinch(.began, scale: 1, rotation: 0, at: centre, time: 0)
        runtime.pinch(.changed, scale: 1, rotation: 0.01, at: centre, time: 0.1)
        #expect(log.events.isEmpty)
        runtime.pinch(.changed, scale: 1, rotation: .pi / 4, at: centre, time: 0.2)
        runtime.pinch(.ended, scale: 1, rotation: .pi / 2, at: centre, time: 0.3)
        #expect(log.events == ["rotate 45 v444", "rotated 90"])

        let older = Log()
        let old = self.runtime(Color.red.frame(width: 40, height: 20)
            .gesture(MagnificationGesture().onChanged { older.events.append("scale \(f2($0))") })
            .gesture(RotationGesture().onEnded { older.events.append("angle \(Int($0.degrees.rounded()))") }))
        // The inner gesture is the deepest target; the outer (not simultaneous) one is not fed.
        old.pinch(.began, scale: 1, rotation: 0, at: centre, time: 0)
        old.pinch(.changed, scale: 1.5, rotation: 1, at: centre, time: 0.1)
        old.pinch(.ended, scale: 1.5, rotation: 1, at: centre, time: 0.2)
        #expect(older.events == ["scale 150"])
    }

    @Test func simultaneousAncestorsSharePinchesAndPresses() {
        let log = Log()
        let runtime = runtime(VStack {
            Color.red.frame(width: 40, height: 20).gesture(MagnifyGesture().onChanged { log.events.append("inner \(f2($0.magnification))") })
        }.simultaneousGesture(MagnifyGesture().onChanged { log.events.append("outer \(f2($0.magnification))") }))
        runtime.pinch(.began, scale: 1, rotation: 0, at: centre, time: 0)
        runtime.pinch(.changed, scale: 1.5, rotation: 0, at: centre, time: 0.1)
        runtime.pinch(.ended, scale: 1.5, rotation: 0, at: centre, time: 0.2)
        #expect(log.events == ["inner 150", "outer 150"])

        // A press a button takes reaches the simultaneous gesture above it, with its own frame
        // deciding "inside"; a plain `gesture` above the button does not run.
        let presses = Log()
        let button = self.runtime(Button("Tap") { presses.events.append("button") }
            .simultaneousGesture(TapGesture().onEnded { presses.events.append("tap") })
            .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { presses.events.append("drag \(Int($0.translation.width))") })
            .gesture(TapGesture().onEnded { presses.events.append("outer") }))
        button.pointerDown(at: centre, time: 0)
        button.pointerMoved(to: CGPoint(x: 103, y: 50), time: 0.05)
        button.pointerUp(at: CGPoint(x: 103, y: 50), time: 0.1)
        #expect(presses.events == ["button", "tap", "drag 3"])
    }

    @Test func gestureMasks() {
        let log = Log()
        func run(_ mask: GestureMask) -> [String] {
            log.events.removeAll()
            let runtime = self.runtime(Button("Tap") { log.events.append("button") }.gesture(TapGesture().onEnded { log.events.append("gesture") }, including: mask))
            runtime.pointerDown(at: centre, time: 0)
            runtime.pointerUp(at: centre, time: 0.1)
            return log.events
        }
        #expect(run(.all) == ["button"])
        #expect(run(.subviews) == ["button"])
        #expect(run(.gesture) == ["gesture"])
        #expect(run(.none) == [])
        // Without a subview control the view's own gesture runs under `.all`.
        log.events.removeAll()
        let plain = self.runtime(Color.red.frame(width: 40, height: 20).gesture(TapGesture().onEnded { log.events.append("gesture") }, including: .all))
        plain.pointerDown(at: centre, time: 0)
        plain.pointerUp(at: centre, time: 0.1)
        #expect(log.events == ["gesture"])
    }

    @Test func gestureStateTransactions() {
        struct Grown: View {
            @GestureState(reset: { _, transaction in transaction.animation = .linear(duration: 1) }) private var width: CGFloat = 40
            var body: some View {
                Color.red.frame(width: width, height: 20)._probe("box")
                    .gesture(DragGesture(minimumDistance: 0).updating($width) { _, state, transaction in
                        state = 80
                        transaction.animation = .linear(duration: 2)
                    })
            }
        }
        let runtime = runtime(Grown())
        // Probes report the target; the painted rectangle interpolates (AnimationTests).
        func painted() -> String? { runtime.render(scale: 2).commands.map(\.description).first { $0.hasPrefix("fillRect(") } }
        #expect(runtime.probeFrames["box"]?.width == 40)
        runtime.pointerDown(at: centre, time: 0)
        runtime.pointerMoved(to: CGPoint(x: 101, y: 50), time: 0.05)
        // The updating body's transaction animates the state change: 2 s linear, half way after 1 s.
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["box"]?.width == 80)
        #expect(runtime.isAnimating)
        runtime.advanceAnimations(elapsed: 1)
        #expect(painted() == "fillRect(70, 40, 60, 20) #FF383C")
        runtime.advanceAnimations(elapsed: 1.5)
        #expect(painted() == "fillRect(60, 40, 80, 20) #FF383C" && !runtime.isAnimating)
        // The reset closure's transaction animates the reset: 1 s linear, half way after 0.5 s.
        runtime.pointerUp(at: CGPoint(x: 101, y: 50), time: 0.1)
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["box"]?.width == 40)
        #expect(runtime.isAnimating)
        runtime.advanceAnimations(elapsed: 0.5)
        #expect(painted() == "fillRect(70, 40, 60, 20) #FF383C")
        runtime.advanceAnimations(elapsed: 1)
        #expect(painted() == "fillRect(80, 40, 40, 20) #FF383C" && !runtime.isAnimating)
    }
}
#endif
