// Dynamic Type (sw-dynamic-type, Docs/elements/Text.md): the text styles at other content size
// categories set through `dynamicTypeSize`, a `@ScaledMetric` following the body style, and the
// range form clamping an accessibility size. Measured on the iPhone simulator; the macOS twin
// (`text/dynamic-type`) shows what macOS does with the same modifiers.
import SwiftUI
import FixtureKit

/// A square whose side scales with the body text style.
struct ScaledBox: View {
    @ScaledMetric(relativeTo: .body) var side: CGFloat = 20
    var body: some View { Color.red.frame(width: side, height: side) }
}

public enum IOSDynamicTypeFixtures {
    @MainActor static func styles(_ size: DynamicTypeSize, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Large Title").font(.largeTitle).probe("largeTitle")
            Text("Title").font(.title).probe("title")
            Text("Headline").font(.headline).probe("headline")
            Text("Body").probe("body")
            Text("Footnote").font(.footnote).probe("footnote")
            Text("Caption 2").font(.caption2).probe("caption2")
            Text("Bold").bold().probe("bold")
            Text(TextMetricsRequests.paragraph).frame(width: 300, alignment: .leading).probe("paragraph")
            ScaledBox().probe("scaled")
        }
        .frame(width: width, alignment: .leading)
        .dynamicTypeSize(size)
    }

    public static let xSmall = Fixture("ios/text/dynamic-xsmall", size: CGSize(width: 320, height: 300)) {
        styles(.xSmall, width: 300).probe("stack")
    }.platform(.iOS)

    public static let xxxLarge = Fixture("ios/text/dynamic-xxxlarge", size: CGSize(width: 320, height: 440)) {
        styles(.xxxLarge, width: 300).probe("stack")
    }.platform(.iOS)

    public static let accessibility4 = Fixture("ios/text/dynamic-ax4", size: CGSize(width: 340, height: 760)) {
        styles(.accessibility4, width: 320).probe("stack")
    }.platform(.iOS)

    /// macOS has no Dynamic Type: the same modifiers on the Mac (what happens is measured here).
    public static let mac = Fixture("text/dynamic-type", size: CGSize(width: 320, height: 240)) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Body").font(.body).probe("large")
            Text("Body").font(.body).dynamicTypeSize(.accessibility5).probe("ax5")
            Text("Body").font(.body).dynamicTypeSize(.xSmall).probe("xsmall")
            ScaledBox().probe("scaledLarge")
            ScaledBox().dynamicTypeSize(.accessibility5).probe("scaledAX5")
        }
        .probe("stack")
    }

    /// `dynamicTypeSize(...xLarge)` under an accessibility size clamps to xLarge; a nested
    /// `.xSmall` wins over the range.
    public static let clamped = Fixture("ios/text/dynamic-clamped", size: CGSize(width: 320, height: 160)) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clamped").probe("clamped")
            ScaledBox().probe("scaled")
            Text("Clamped").dynamicTypeSize(.xSmall).probe("small")
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .dynamicTypeSize(.accessibility4)
        .probe("stack")
    }.platform(.iOS)

    public static let all: [Fixture] = [xSmall, xxxLarge, accessibility4, clamped, mac]
}
