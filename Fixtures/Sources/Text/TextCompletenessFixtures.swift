import SwiftUI
import FixtureKit

/// Phase 2 Text completeness: concatenation with mixed styles, lineLimit, truncationMode,
/// multilineTextAlignment, lineSpacing, wrapped paragraphs and baseline alignment of wrapped text.
extension TextFixtures {
    typealias R = TextMetricsRequests

    public static let concatenation = Fixture("text/concatenation", size: CGSize(width: 400, height: 300)) {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Hello, ").bold() + Text("World")).probe("boldPlain")
            (Text("Big ").font(.largeTitle) + Text("small")).probe("mixedSize")
            (Text("Red ").foregroundColor(.red) + Text("Blue").foregroundColor(.blue)).probe("colors")
            (Text("Title ") + Text("italic").italic()).font(.title).probe("titleItalic")
            VStack(alignment: .leading, spacing: 0) {
                (Text("Env ") + Text("bold").bold()).probe("envBold")
            }
            .font(.title)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                (Text("Big ").font(.largeTitle) + Text("small")).probe("mixedBaseline")
                Color.red.frame(width: 10, height: 10).probe("baselineBox")
            }
            (Text(R.richParagraphHead).bold() + Text(R.richParagraphTail))
                .frame(width: 150, alignment: .topLeading).probe("wrappedRich")
        }
        .probe("column")
    }

    public static let lineLimit = Fixture("text/line-limit", size: CGSize(width: 400, height: 420)) {
        VStack(alignment: .leading, spacing: 0) {
            Text(R.paragraph).lineLimit(1).probe("limit1").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(2).probe("limit2").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(3).probe("limit3").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(10).probe("limit10").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(...2).probe("upTo2").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(1...3).probe("range1to3").frame(width: 150, alignment: .topLeading)
            Text("Hello").lineLimit(1).probe("short")
            Text("Hello").lineLimit(2, reservesSpace: true).probe("reserved2")
            Text("Hello").lineLimit(2...4).probe("range2to4")
            Text("Hello").lineLimit(3...).probe("atLeast3")
        }
        .probe("column")
    }

    public static let truncation = Fixture("text/truncation", size: CGSize(width: 400, height: 200)) {
        VStack(alignment: .leading, spacing: 0) {
            Text(R.paragraph).lineLimit(1).truncationMode(.head).probe("head").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(1).truncationMode(.middle).probe("middle").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(1).truncationMode(.tail).probe("tail").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineLimit(1).probe("wide").frame(width: 260, alignment: .topLeading)
            Text(R.paragraph).lineLimit(2).truncationMode(.middle).probe("middle2").frame(width: 150, alignment: .topLeading)
            Text("Hello").truncationMode(.head).probe("fits")
        }
        .probe("column")
    }

    public static let alignment = Fixture("text/alignment", size: CGSize(width: 400, height: 300)) {
        VStack(spacing: 0) {
            Text(R.paragraph).multilineTextAlignment(.leading).probe("leading").frame(width: 200, alignment: .top)
            Text(R.paragraph).multilineTextAlignment(.center).probe("center").frame(width: 200, alignment: .top)
            Text(R.paragraph).multilineTextAlignment(.trailing).probe("trailing").frame(width: 200, alignment: .top)
            Text(R.newlineShort).multilineTextAlignment(.trailing).probe("newline")
            Text(R.newlineShort).multilineTextAlignment(.center).probe("newlineCenter")
            Text("Hi").multilineTextAlignment(.trailing).probe("single").frame(width: 200, alignment: .leading)
        }
        .probe("column")
    }

    public static let lineSpacing = Fixture("text/line-spacing", size: CGSize(width: 400, height: 320)) {
        VStack(alignment: .leading, spacing: 0) {
            Text(R.paragraph).lineSpacing(4).probe("s4").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).lineSpacing(10).probe("s10").frame(width: 150, alignment: .topLeading)
            Text(R.paragraph).font(.body).lineSpacing(4).probe("bodyS4").frame(width: 150, alignment: .topLeading)
            Text("Hello").lineSpacing(10).probe("single")
        }
        .probe("column")
    }

    public static let paragraphs = Fixture("text/paragraphs", size: CGSize(width: 400, height: 420)) {
        VStack(alignment: .leading, spacing: 0) {
            // 134 fits the drawn width of "Layout must wrap this" (133.5) but not its trailing space (137).
            Text(R.paragraph).probe("hanging").frame(width: 134, alignment: .topLeading)
            Text(R.paragraph).probe("w100").frame(width: 100, alignment: .topLeading)
            Text(R.paragraph).probe("w300").frame(width: 300, alignment: .topLeading)
            Text(R.longWord).probe("longWord").frame(width: 60, alignment: .topLeading)
            Text(R.twoParagraphs).probe("twoFree")
            Text(R.twoParagraphs).probe("twoWrapped").frame(width: 220, alignment: .topLeading)
            Text(R.paragraph).font(.title).probe("titleWrap").frame(width: 300, alignment: .topLeading)
        }
        .probe("column")
    }

    public static let baselineWrapped = Fixture("text/baseline-wrapped", size: CGSize(width: 400, height: 200)) {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(R.paragraph).probe("lastWrapped").frame(width: 120, alignment: .topLeading)
                Text("End").font(.largeTitle).probe("lastEnd")
                Color.red.frame(width: 10, height: 10).probe("lastBox")
            }
            .probe("last")
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(R.paragraph).probe("firstWrapped").frame(width: 120, alignment: .topLeading)
                Text("End").font(.largeTitle).probe("firstEnd")
                Color.red.frame(width: 10, height: 10).probe("firstBox")
            }
            .probe("first")
        }
        .probe("column")
    }

    public static let completeness: [Fixture] = [concatenation, lineLimit, truncation, alignment, lineSpacing, paragraphs, baselineWrapped]
}
