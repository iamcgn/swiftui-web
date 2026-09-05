// Text under height pressure: a paragraph proposed less height than its lines need keeps
// floor(height / line pitch) lines, at least one, and truncates the last (measured 2026-09-04).
// Recorded for later: applying the rule showed our stacks propose flexible children less height
// than SwiftUI does, so the fixtures live under `pressure/`, outside the enabled prefixes, until
// the stack distribution is measured (Docs/elements/Text.md).
import SwiftUI
import FixtureKit

public enum TextPressureFixtures {
    static let paragraph = "Layout must wrap this sentence onto several lines inside a narrow frame."

    public static let heights = Fixture("pressure/heights", size: CGSize(width: 760, height: 200), content: {
        HStack(alignment: .top, spacing: 10) {
            ForEach([8, 20, 32, 40, 48, 70], id: \.self) { height in
                Text(paragraph).probe("t\(height)").frame(width: 110, height: CGFloat(height), alignment: .topLeading).probe("h\(height)")
            }
        }
        .probe("row")
    })

    /// A stack taller than its window: the flexible text gives up lines.
    public static let overflow = Fixture("pressure/overflow", size: CGSize(width: 200, height: 120), content: {
        VStack(spacing: 8) {
            Color.red.frame(height: 40).probe("top")
            Text(paragraph).frame(width: 150, alignment: .leading).probe("text")
            Color.blue.frame(height: 40).probe("bottom")
        }
        .probe("stack")
    })

    public static let all: [Fixture] = [heights, overflow]
}
