// Rich text (Docs/elements/Text.md, "Rich text"): markdown in string literals, AttributedString
// runs, dates and formatted values, and images inline in text.
import SwiftUI
import FixtureKit

public enum TextRichFixtures {
    /// A fixed instant: 2026-05-28 20:26:40 UTC (shown at UTC in en_US).
    public static let instant = Date(timeIntervalSince1970: 1_780_000_000)

    public static let markdown = Fixture("text/markdown", size: CGSize(width: 400, height: 300)) {
        VStack(alignment: .leading, spacing: 4) {
            Text("Plain **bold** and _italic_ and ***both*** done").probe("mixed")
            Text("**bold**").probe("bold")
            Text("_italic_").probe("italic")
            Text("***both***").probe("both")
            Text("`code`").probe("code")
            Text("~~struck~~").probe("struck")
            Text("[a link](https://example.com)").probe("link")
            Text("Call **now** or [visit](https://example.com) today").probe("linkMixed")
            Text(verbatim: "**not** markdown").probe("verbatim")
            Text("Escaped \\*stars\\*").probe("escaped")
            Text("Mono `code` and plain").font(.title3).probe("codeTitle")
        }
        .probe("column")
    }

    public static let attributed = Fixture("text/attributed", size: CGSize(width: 400, height: 200)) {
        VStack(alignment: .leading, spacing: 4) {
            Text(fixtureRichString()).probe("attributed")
            Text(fixtureIntentString()).probe("intents")
            Text(AttributedString("Plain attributed")).probe("plain")
        }
        .probe("column")
    }

    public static let dates = Fixture("text/dates", size: CGSize(width: 400, height: 200)) {
        VStack(alignment: .leading, spacing: 4) {
            Text(instant, style: .date).probe("date")
            Text(instant, style: .time).probe("time")
            Text(3.14159, format: .number).probe("number")
            Text(1234, format: .number).probe("int")
            Text(0.25, format: .percent).probe("percent")
            Text(12.5, format: .currency(code: "USD")).probe("currency")
            #if !os(WASI)
            Text(instant, format: .dateTime.year().month().day()).probe("dateTime")
            #else
            // No `Date.FormatStyle` on wasm: the same words through the date style keep the frames.
            Text(instant, style: .date).probe("dateTime")
            #endif
        }
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        .environment(\.locale, Locale(identifier: "en_US"))
        .probe("column")
    }

    public static let inlineImage = Fixture("text/inline-image", size: CGSize(width: 400, height: 200)) {
        VStack(alignment: .leading, spacing: 4) {
            Text(Image(systemName: "star")).probe("star")
            (Text(Image(systemName: "star")) + Text(" Starred")).probe("starText")
            (Text("Rate ") + Text(Image(systemName: "star.fill")) + Text(" now")).probe("between")
            Text(Image(systemName: "star")).font(.title).probe("starTitle")
            (Text(Image(systemName: "chevron.right")) + Text(" Next")).probe("chevron")
            (Text(Image(systemName: "star")) + Text(" Bold")).bold().probe("boldStar")
        }
        .probe("column")
    }

    public static let all: [Fixture] = [markdown, attributed, dates, inlineImage]
}
