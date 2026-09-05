// `redacted(reason:)`: placeholders stand in for text and images; `privacySensitive` views hide
// under the privacy reason; `unredacted` opts out.
import SwiftUI
import FixtureKit

public enum RedactedFixtures {
    public static let placeholder = Fixture("redacted/placeholder", size: CGSize(width: 360, height: 360), content: {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plain text stays").probe("plain")
            Group {
                Text("Redacted text").probe("text")
                Text("Two lines of redacted text that wrap around inside a narrow frame").frame(width: 200, alignment: .leading).probe("wrapped")
                Text("Title").font(.title).probe("title")
                HStack(spacing: 10) {
                    Image(systemName: "star").font(.title).probe("symbol")
                    Button("Button") {}.probe("button")
                    Toggle("Toggle", isOn: .constant(true)).probe("toggle")
                }
                .probe("controls")
                Color.blue.frame(width: 80, height: 20).probe("color")
                Circle().fill(Color.green).frame(width: 30, height: 30).probe("shape")
                Text("Unredacted inside").unredacted().probe("unredacted")
                Text("Secret").privacySensitive().probe("sensitive")
            }
            .redacted(reason: .placeholder)
        }
        .probe("stack")
    })

    public static let privacy = Fixture("redacted/privacy", size: CGSize(width: 360, height: 160), content: {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visible under privacy").probe("visible")
            Text("Hidden secret").privacySensitive().probe("secret")
            HStack(spacing: 10) { Text("Balance:"); Text("$1,234").privacySensitive().probe("amount") }.probe("row")
            Text("Invalidated").probe("invalidated").redacted(reason: .invalidated)
        }
        .redacted(reason: .privacy)
        .probe("stack")
    })

    /// Placeholder widths: the same character counts in different glyphs and sizes.
    public static let widths = Fixture("redacted/widths", size: CGSize(width: 520, height: 420), content: {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([11, 13, 17, 22, 26], id: \.self) { size in
                HStack(spacing: 12) {
                    Text("iiiiiiiiii").font(.system(size: CGFloat(size))).probe("i\(size)")
                    Text("MMMMMMMMMM").font(.system(size: CGFloat(size))).probe("M\(size)")
                    Text("a b c d e").font(.system(size: CGFloat(size))).probe("sp\(size)")
                    Text("12345").font(.system(size: CGFloat(size))).probe("d\(size)")
                }
                .probe("row\(size)")
            }
            Text("abcdefghijklmnopqrstuvwxyzabcdefghijklmn").frame(width: 100, alignment: .leading).probe("wrapNoSpace")
            Text("alpha beta gamma delta epsilon zeta eta").frame(width: 100, alignment: .leading).probe("wrapSpaces")
            Text("Redacted text").bold().probe("bold")
            Text("x").probe("one")
            HStack(spacing: 12) {
                ForEach([11, 13, 17, 22, 26, 34], id: \.self) { size in
                    Image(systemName: "star").font(.system(size: CGFloat(size))).probe("sym\(size)")
                }
                Image(systemName: "star").font(.largeTitle).probe("symLargeTitle")
                Image(systemName: "gear").probe("symGear")
                Image(systemName: "chevron.right").font(.title).probe("symChevron")
            }
            .probe("symbols")
        }
        .redacted(reason: .placeholder)
        .probe("stack")
    })

    public static let all: [Fixture] = [placeholder, privacy, widths]
}
