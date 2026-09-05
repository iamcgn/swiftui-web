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

public enum GestureFixtures {
    public static let basic = Fixture("gesture/basic", size: CGSize(width: 320, height: 340), content: { GestureDemo() })
    public static let all: [Fixture] = [basic]
}
