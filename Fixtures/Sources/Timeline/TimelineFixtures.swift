// TimelineView fixture: the golden holds the first render (no time passes in the harness);
// Playwright/timeline-probe.mjs counts the browser's ticks.
import SwiftUI
import FixtureKit

struct TickCounter: View {
    let date: Date
    @State private var ticks = 0
    var body: some View {
        Text("Ticks: \(ticks)")
            .onChange(of: date) { ticks += 1 }
    }
}

public enum TimelineFixtures {
    public static let basic = Fixture("timeline/basic", size: CGSize(width: 320, height: 100)) {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                TickCounter(date: context.date).probe("periodic")
            }
            TimelineView(.animation) { context in
                Text(context.cadence == .live ? "Live" : "Slow").probe("animation")
            }
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
