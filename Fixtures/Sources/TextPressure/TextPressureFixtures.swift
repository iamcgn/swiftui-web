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

    /// How a VStack shares height with a wrapped text (4 lines, 64 pt at 150 wide) between two
    /// 40 pt colours: windows that fit, that squeeze the text, and with a Spacer.
    @MainActor static func column(spacer: Bool) -> some View {
        VStack(spacing: 0) {
            Color.red.frame(height: 40).probe("top")
            Text(paragraph).frame(width: 150, alignment: .leading).probe("text")
            if spacer { Spacer().probe("spacer") }
            Color.blue.frame(height: 40).probe("bottom")
        }
        .probe("stack")
    }

    public static let stackFits = Fixture("pressure/stack-fits", size: CGSize(width: 200, height: 200), content: { column(spacer: false) })
    public static let stackTight = Fixture("pressure/stack-tight", size: CGSize(width: 200, height: 130), content: { column(spacer: false) })
    public static let stackSpacerFits = Fixture("pressure/stack-spacer-fits", size: CGSize(width: 200, height: 200), content: { column(spacer: true) })
    public static let stackSpacerTight = Fixture("pressure/stack-spacer-tight", size: CGSize(width: 200, height: 130), content: { column(spacer: true) })

    /// Two wrapped texts sharing a short window: which one gives up lines.
    public static let twoTexts = Fixture("pressure/two-texts", size: CGSize(width: 300, height: 90), content: {
        VStack(spacing: 0) {
            Text(paragraph).frame(width: 150, alignment: .leading).probe("first")
            Text("Short second text that wraps twice here").frame(width: 150, alignment: .leading).probe("second")
        }
        .probe("stack")
    })

    /// A text in a row: the HStack proposes the window height.
    public static let rowTight = Fixture("pressure/row-tight", size: CGSize(width: 300, height: 50), content: {
        HStack(spacing: 0) {
            Color.red.frame(width: 40).probe("left")
            Text(paragraph).frame(width: 150, alignment: .leading).probe("text")
        }
        .probe("row")
    })

    static let shortText = "Short second text that wraps twice here"

    public static let twoTextsSwapped = Fixture("pressure/two-texts-swapped", size: CGSize(width: 300, height: 90), content: {
        VStack(spacing: 0) {
            Text(shortText).frame(width: 150, alignment: .leading).probe("second")
            Text(paragraph).frame(width: 150, alignment: .leading).probe("first")
        }
        .probe("stack")
    })

    public static let threeTexts = Fixture("pressure/three-texts", size: CGSize(width: 300, height: 100), content: {
        VStack(spacing: 0) {
            Text(paragraph).frame(width: 150, alignment: .leading).probe("a")
            Text(shortText).frame(width: 150, alignment: .leading).probe("b")
            Text(paragraph).frame(width: 150, alignment: .leading).probe("c")
        }
        .probe("stack")
    })

    @MainActor static func spacerColumn(minLength: CGFloat?) -> some View {
        VStack(spacing: 0) {
            Color.red.frame(height: 40).probe("top")
            Text(paragraph).frame(width: 150, alignment: .leading).probe("text")
            Spacer(minLength: minLength).probe("spacer")
            Color.blue.frame(height: 40).probe("bottom")
        }
        .probe("stack")
    }

    public static let spacerMin0 = Fixture("pressure/spacer-min0", size: CGSize(width: 200, height: 130), content: { spacerColumn(minLength: 0) })
    public static let spacerMin30 = Fixture("pressure/spacer-min30", size: CGSize(width: 200, height: 130), content: { spacerColumn(minLength: 30) })
    public static let spacerRoomy = Fixture("pressure/spacer-roomy", size: CGSize(width: 200, height: 150), content: { spacerColumn(minLength: nil) })

    /// The text alone under a squeeze: what it answers to a stack's proposal of exactly 25 and 45.
    public static let alone25 = Fixture("pressure/alone25", size: CGSize(width: 300, height: 25), content: {
        VStack(spacing: 0) { Text(paragraph).frame(width: 150, alignment: .leading).probe("text") }.probe("stack")
    })
    public static let alone45 = Fixture("pressure/alone45", size: CGSize(width: 300, height: 45), content: {
        VStack(spacing: 0) { Text(paragraph).frame(width: 150, alignment: .leading).probe("text") }.probe("stack")
    })

    public static let all: [Fixture] = [heights, overflow, stackFits, stackTight, stackSpacerFits, stackSpacerTight, twoTexts, rowTight,
                                        twoTextsSwapped, threeTexts, spacerMin0, spacerMin30, spacerRoomy, alone25, alone45]
}
