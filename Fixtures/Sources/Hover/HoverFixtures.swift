// Hover: `onHover`, `onContinuousHover`, `help` tooltips and `pointerStyle`. The golden is the
// resting state; the browser behaviour is checked by Playwright/hover-probe.mjs.
import SwiftUI
import FixtureKit

struct HoverDemo: View {
    @State private var hovering = false
    @State private var location: CGPoint?
    @State private var entries = 0

    var body: some View {
        VStack(spacing: 16) {
            Text(hovering ? "Inside" : "Outside")
                .padding(10)
                .background(hovering ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                .onHover { inside in
                    hovering = inside
                    if inside { entries += 1 }
                }
                .probe("hoverBox")
            Text(location.map { "At \(Int($0.x)), \(Int($0.y))" } ?? "No pointer")
                .frame(width: 160, height: 40)
                .background(Color.green.opacity(0.2))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): location = point
                    case .ended: location = nil
                    }
                }
                .probe("continuous")
            HStack(spacing: 20) {
                Text("Help me").padding(6).background(Color.orange.opacity(0.3)).help("A helpful tooltip").probe("help")
                Text("Link").padding(6).background(Color.purple.opacity(0.2)).pointerStyle(.link).probe("link")
                Text("Text").padding(6).background(Color.yellow.opacity(0.3)).pointerStyle(.horizontalText).probe("ibeam")
            }
            .probe("row")
            Text("Entries: \(entries)").probe("entries")
        }
        .probe("stack")
    }
}

public enum HoverFixtures {
    public static let basic = Fixture("hover/basic", size: CGSize(width: 320, height: 240), content: { HoverDemo() })
    public static let all: [Fixture] = [basic]
}
