// Text decoration fixtures: underline and strikethrough (line styles, patterns, colours, on the
// text and on the view), text case, and baseline offsets.
import SwiftUI
import FixtureKit

public enum TextStyleFixtures {
    public static let underline = Fixture("textstyle/underline", size: CGSize(width: 260, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Underlined").underline().probe("body")
            Text("Title line").font(.title).underline().probe("title")
            Text("Colored").underline(true, color: .red).probe("colored")
            Text("Caption small").font(.caption).underline().probe("caption")
            Text("Bold Under").bold().underline().probe("bold")
            (Text("Hello ").underline() + Text("World")).probe("partial")
            VStack(alignment: .leading, spacing: 4) {
                Text("First").probe("first")
                Text("Second").underline(false).probe("second")
            }
            .underline()
            .probe("viewLevel")
            Text("Both").underline().strikethrough().probe("both")
        }
        .probe("stack")
    }

    public static let strikethrough = Fixture("textstyle/strikethrough", size: CGSize(width: 260, height: 240)) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Struck").strikethrough().probe("body")
            Text("Title strike").font(.title).strikethrough().probe("title")
            Text("Red strike").strikethrough(true, color: .red).probe("colored")
            Text("Caption strike").font(.caption).strikethrough().probe("caption")
            Text("Bold strike").bold().strikethrough().probe("bold")
            (Text("Mixed ") + Text("line").strikethrough()).probe("partial")
            Text("Large strike").font(.largeTitle).strikethrough().probe("large")
        }
        .probe("stack")
    }

    public static let patterns = Fixture("textstyle/patterns", size: CGSize(width: 260, height: 260)) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Solid").underline(true, pattern: .solid).probe("solid")
            Text("Dotted").underline(true, pattern: .dot).probe("dot")
            Text("Dashed").underline(true, pattern: .dash).probe("dash")
            Text("Dash dot").underline(true, pattern: .dashDot).probe("dashDot")
            Text("Dash dot dot").underline(true, pattern: .dashDotDot).probe("dashDotDot")
            Text("Dash strike").strikethrough(true, pattern: .dash, color: .blue).probe("dashStrike")
            Text("Dotted title").font(.title).underline(true, pattern: .dot).probe("dotTitle")
        }
        .probe("stack")
    }

    public static let textCase = Fixture("textstyle/case", size: CGSize(width: 260, height: 140)) {
        VStack(alignment: .leading, spacing: 12) {
            Text("mixed Case").textCase(.uppercase).probe("upper")
            Text("mixed Case").textCase(.lowercase).probe("lower")
            Text("mixed Case").textCase(nil).probe("none")
            VStack(alignment: .leading) { Text("mixed Case").probe("inherited") }.textCase(.uppercase).probe("group")
        }
        .probe("stack")
    }

    public static let baseline = Fixture("textstyle/baseline", size: CGSize(width: 260, height: 160)) {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Base").probe("base")
                Text("Up").baselineOffset(6).probe("up")
                Text("Down").baselineOffset(-4).probe("down")
            }
            .probe("row")
            HStack(spacing: 12) {
                Text("Base").probe("centerBase")
                Text("Up").baselineOffset(6).probe("centerUp")
            }
            .probe("centerRow")
            Text("Raised").baselineOffset(8).probe("raised")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [underline, strikethrough, patterns, textCase, baseline]
}
