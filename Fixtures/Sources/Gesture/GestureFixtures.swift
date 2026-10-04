// Gestures: drag, long press, double tap and a sequenced long press + drag. The golden is the
// resting state; Playwright/gesture-probe.mjs drives the browser.
import SwiftUI
import FixtureKit

struct GestureDemo: View {
    @State private var offset = CGSize.zero
    @State private var dragging = false
    @State private var longPresses = 0
    @State private var pressing = false
    @State private var doubleTaps = 0
    @GestureState private var held = false

    var body: some View {
        VStack(spacing: 14) {
            Text(dragging ? "Dragging \(Int(offset.width)), \(Int(offset.height))" : "Drag the box").probe("dragLabel")
            Color.blue.frame(width: 80, height: 50)
                .offset(offset)
                .gesture(DragGesture()
                    .onChanged { value in offset = value.translation; dragging = true }
                    .onEnded { _ in dragging = false; offset = .zero })
                .probe("dragBox")
            Text(pressing ? "Pressing" : "Long presses: \(longPresses)").probe("pressLabel")
            Color.orange.frame(width: 80, height: 40)
                .onLongPressGesture(minimumDuration: 0.5) { longPresses += 1 } onPressingChanged: { pressing = $0 }
                .probe("pressBox")
            Text("Double taps: \(doubleTaps)").probe("tapLabel")
            Color.green.frame(width: 80, height: 40)
                .onTapGesture(count: 2) { doubleTaps += 1 }
                .probe("tapBox")
            Text(held ? "Held" : "Idle").probe("heldLabel")
            Color.purple.frame(width: 80, height: 40)
                .gesture(LongPressGesture(minimumDuration: 0.3).updating($held) { value, state, _ in state = value })
                .probe("heldBox")
        }
        .probe("stack")
    }
}

/// Pinches: a box that scales and turns with a magnify + rotate gesture, and a `@GestureState`
/// set while a pinch runs. The golden is the resting state; the probe pinches with control-wheel
/// events, Safari-style gesture events and two touches.
struct PinchDemo: View {
    @State private var scale: CGFloat = 1
    @State private var angle: Angle = .zero
    @GestureState private var pinching = false

    private var label: String {
        let hundredths = Int((scale * 100).rounded())
        let fraction = hundredths % 100
        return "Scale \(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction), \(Int(angle.degrees.rounded()))°"
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(label).probe("pinchLabel")
            Color.teal.frame(width: 100, height: 70)
                .scaleEffect(scale)
                .rotationEffect(angle)
                .gesture(MagnifyGesture().simultaneously(with: RotateGesture())
                    .onChanged { value in
                        if let magnify = value.first { scale = magnify.magnification }
                        if let rotate = value.second { angle = rotate.rotation }
                    }
                    .onEnded { _ in scale = 1; angle = .zero })
                .probe("pinchBox")
            Text(pinching ? "Pinching" : "Rest").probe("stateLabel")
            Color.indigo.frame(width: 100, height: 40)
                .gesture(MagnifyGesture().updating($pinching) { _, state, _ in state = true })
                .probe("stateBox")
        }
        .probe("stack")
    }
}

public enum GestureFixtures {
    public static let basic = Fixture("gesture/basic", size: CGSize(width: 320, height: 340), content: { GestureDemo() })
    public static let pinch = Fixture("gesture/pinch", size: CGSize(width: 320, height: 240), content: { PinchDemo() })
    public static let all: [Fixture] = [basic, pinch]
}
