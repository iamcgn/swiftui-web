import SwiftUI
import FixtureKit

public enum TextFixtures {
    public static let hello = Fixture("text/hello", size: CGSize(width: 200, height: 100)) {
        Text("Hello").probe("hello")
    }

    public static let styles = Fixture("text/styles", size: CGSize(width: 400, height: 400)) {
        VStack(alignment: .leading, spacing: 0) {
            Text(TextMetricsRequests.sample).font(.largeTitle).probe("largeTitle")
            Text(TextMetricsRequests.sample).font(.title).probe("title")
            Text(TextMetricsRequests.sample).font(.title2).probe("title2")
            Text(TextMetricsRequests.sample).font(.title3).probe("title3")
            Text(TextMetricsRequests.sample).font(.headline).probe("headline")
            Text(TextMetricsRequests.sample).font(.subheadline).probe("subheadline")
            Text(TextMetricsRequests.sample).font(.body).probe("body")
            Text(TextMetricsRequests.sample).font(.callout).probe("callout")
            Text(TextMetricsRequests.sample).font(.footnote).probe("footnote")
            Text(TextMetricsRequests.sample).font(.caption).probe("caption")
            Text(TextMetricsRequests.sample).font(.caption2).probe("caption2")
        }
        .probe("column")
    }

    public static let systemFonts = Fixture("text/system-fonts", size: CGSize(width: 400, height: 400)) {
        VStack(alignment: .leading, spacing: 0) {
            Text(TextMetricsRequests.sample).font(.system(size: 10)).probe("s10")
            Text(TextMetricsRequests.sample).font(.system(size: 12)).probe("s12")
            Text(TextMetricsRequests.sample).font(.system(size: 20)).probe("s20")
            Text(TextMetricsRequests.sample).font(.system(size: 24)).probe("s24")
            Text(TextMetricsRequests.sample).font(.system(size: 32)).probe("s32")
            Text(TextMetricsRequests.sample).font(.system(size: 20, weight: .light)).probe("light")
            Text(TextMetricsRequests.sample).font(.system(size: 20, weight: .medium)).probe("medium")
            Text(TextMetricsRequests.sample).font(.system(size: 20, weight: .bold)).probe("bold")
            Text(TextMetricsRequests.sample).font(.system(size: 20, weight: .black)).probe("black")
            Text(TextMetricsRequests.sample).font(.system(size: 20, design: .rounded)).probe("rounded")
            Text(TextMetricsRequests.sample).font(.system(size: 20, design: .serif)).probe("serif")
            Text(TextMetricsRequests.sample).font(.system(size: 20, design: .monospaced)).probe("monospaced")
        }
    }

    public static let wrapped = Fixture("text/wrapped", size: CGSize(width: 400, height: 300)) {
        VStack(alignment: .leading, spacing: 0) {
            Text(TextMetricsRequests.paragraph).probe("narrow").frame(width: 150, alignment: .topLeading).probe("narrowFrame")
            Text(TextMetricsRequests.paragraph).probe("wide").frame(width: 260, alignment: .topLeading)
            Text(TextMetricsRequests.paragraph).probe("free")
        }
        .probe("column")
    }

    public static let vstackSpacing = Fixture("text/vstack-spacing", size: CGSize(width: 200, height: 200)) {
        VStack {
            Text("One").probe("one")
            Text("Two").probe("two")
            Color.red.frame(width: 50, height: 10).probe("box")
            Text("Three").probe("three")
        }
        .probe("stack")
    }

    public static let vstackSpacingMixed = Fixture("text/vstack-spacing-mixed", size: CGSize(width: 200, height: 300)) {
        VStack {
            Text("Hg").font(.largeTitle).probe("large1")
            Text("Hg").probe("body1")
            Text("Hg").font(.largeTitle).probe("large2")
            Color.red.frame(width: 50, height: 10).probe("box")
            Text("Hg").font(.largeTitle).probe("large3")
            Text("Hg").font(.caption2).probe("caption")
            Text("Hg").probe("body2")
        }
        .probe("stack")
    }

    public static let hstackSpacing = Fixture("text/hstack-spacing", size: CGSize(width: 300, height: 100)) {
        HStack {
            Text("One").probe("one")
            Text("Two").probe("two")
            Color.red.frame(width: 10, height: 10).probe("box")
            Text("Three").probe("three")
        }
        .probe("stack")
    }

    public static let hstackBaseline = Fixture("text/hstack-baseline", size: CGSize(width: 300, height: 100)) {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Big").font(.largeTitle).probe("big")
                Text("small").probe("small")
                Color.red.frame(width: 10, height: 10).probe("box")
            }
            .probe("first")
            HStack(alignment: .lastTextBaseline) {
                Text("Big").font(.largeTitle).probe("big2")
                Text("small").probe("small2")
            }
            .probe("last")
        }
    }

    public static let modifiers = Fixture("text/modifiers", size: CGSize(width: 300, height: 200)) {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bold").bold().probe("bold")
            Text("Bold").fontWeight(.bold).probe("fontWeightBold")
            Text("Bold").font(.body.bold()).probe("fontBold")
            Text("Bold").font(.body.weight(.bold)).probe("fontWeight700")
            Text("Bold").fontWeight(.semibold).probe("semibold")
            Text("Weight").fontWeight(.semibold).probe("weight")
            VStack(alignment: .leading, spacing: 0) {
                Text("Env").probe("env")
            }
            .font(.title)
            Text("Count: \(0)").font(.title).probe("interpolated")
            Text("Count: \(0)").probe("interpolatedBody")
        }
    }

    public static let all: [Fixture] = [hello, styles, systemFonts, wrapped, vstackSpacing, vstackSpacingMixed, hstackSpacing, hstackBaseline, modifiers]
}
