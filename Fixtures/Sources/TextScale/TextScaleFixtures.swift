// textScale(.secondary) and textSelection: the secondary scale shrinks text by a fixed factor
// per text style (measured 2026-09-05); selectable text lays out and paints unchanged.
import SwiftUI
import FixtureKit

public enum TextScaleFixtures {
    static let paragraph = "Layout must wrap this sentence onto several lines inside a narrow frame."

    /// Every text style at the default and the secondary scale, side by side.
    public static let styles = Fixture("textscale/styles", size: CGSize(width: 520, height: 420), content: {
        let styles: [(String, Font)] = [("largeTitle", .largeTitle), ("title", .title), ("title2", .title2), ("title3", .title3),
                                        ("headline", .headline), ("body", .body), ("callout", .callout), ("subheadline", .subheadline),
                                        ("footnote", .footnote), ("caption", .caption), ("caption2", .caption2), ("s20", .system(size: 20))]
        VStack(alignment: .leading, spacing: 2) {
            ForEach(styles, id: \.0) { name, font in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Hello").font(font).probe("\(name)-default")
                    Text("Hello").font(font).textScale(.secondary).probe("\(name)-secondary")
                }
                .probe("\(name)-row")
            }
        }
        .probe("column")
    })

    /// A wrapped paragraph at the secondary scale: line pitch and wrap width follow the scaled font.
    public static let wrapped = Fixture("textscale/wrapped", size: CGSize(width: 400, height: 200), content: {
        VStack(alignment: .leading, spacing: 8) {
            Text(paragraph).frame(width: 150, alignment: .leading).probe("default")
            Text(paragraph).textScale(.secondary).frame(width: 150, alignment: .leading).probe("secondary")
            Text(paragraph).textScale(.secondary, isEnabled: false).frame(width: 150, alignment: .leading).probe("disabled")
        }
        .probe("column")
    })

    /// Selection does not change layout; the environment value is readable.
    public static let selection = Fixture("textscale/selection", size: CGSize(width: 300, height: 100), content: {
        VStack(spacing: 8) {
            Text("Selectable text").textSelection(.enabled).probe("enabled")
            Text("Plain text").textSelection(.disabled).probe("disabled")
        }
        .probe("column")
    })


    public static let all: [Fixture] = [styles, wrapped, selection]
}
