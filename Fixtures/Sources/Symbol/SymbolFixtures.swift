// SF Symbol fixtures. `symbol/catalog` measures the layout size of common symbols at the body
// font (the metrics table, scripts/symbol-metrics-table.py); `symbol/basic` measures the rules:
// font sizes and weights, image scales, baseline and label alignment, resizing and colour. The
// glyphs themselves are drawn from an open icon set (approximate), so the goldens are used for
// frames only in Tier B.
import SwiftUI
import FixtureKit

public enum SymbolFixtures {
    /// Symbols the metrics table records (a row per ten).
    public static let catalogNames: [String] = [
        "star", "star.fill", "heart", "heart.fill", "checkmark", "xmark", "plus", "minus", "chevron.right", "chevron.left",
        "chevron.down", "chevron.up", "gear", "gearshape", "gearshape.fill", "magnifyingglass", "trash", "trash.fill", "pencil", "folder",
        "folder.fill", "doc", "doc.text", "person", "person.fill", "person.circle", "house", "house.fill", "bell", "bell.fill",
        "envelope", "calendar", "clock", "info.circle", "exclamationmark.triangle", "arrow.right", "arrow.left", "arrow.up", "arrow.down", "square.and.arrow.up",
        "ellipsis", "circle", "circle.fill", "square", "square.fill", "photo", "camera", "play.fill", "pause.fill", "bookmark",
        "tag", "lock", "lock.open", "paperplane", "cart", "map", "globe", "link", "eye", "eye.slash",
        "questionmark.circle", "checkmark.circle", "checkmark.circle.fill", "xmark.circle", "xmark.circle.fill", "plus.circle", "plus.circle.fill", "minus.circle", "line.3.horizontal", "list.bullet",
        "sun.max", "moon", "cloud", "bolt", "flame", "leaf", "wifi", "speaker.wave.2", "mic", "phone",
        "message", "bubble.left", "hand.thumbsup", "flag", "pin", "location", "car", "airplane", "gift", "creditcard",
        "chart.bar", "square.grid.2x2", "slider.horizontal.3", "arrow.clockwise", "arrow.counterclockwise", "arrow.up.arrow.down", "arrow.uturn.left", "sidebar.left", "square.and.pencil", "ellipsis.circle",
        "arrow.down.circle", "arrow.up.circle", "arrow.right.circle", "arrow.left.circle", "chevron.right.circle", "checkmark.square", "square.dashed", "rectangle", "rectangle.portrait", "triangle",
        "exclamationmark.circle", "exclamationmark.circle.fill", "info.circle.fill", "questionmark", "exclamationmark", "number", "at", "percent", "dollarsign.circle", "textformat",
        "bold", "italic", "underline", "text.alignleft", "text.aligncenter", "text.alignright", "text.justify", "list.number", "checklist", "quote.opening",
        "square.and.arrow.down", "arrow.down.to.line", "arrow.up.to.line", "doc.on.doc", "doc.on.clipboard", "printer", "scissors", "paperclip", "key", "shield",
        "ant", "chevron.left.forwardslash.chevron.right", "terminal", "cylinder", "desktopcomputer", "iphone", "headphones", "music.note", "video", "mic.slash",
        "bell.slash", "battery.100", "antenna.radiowaves.left.and.right", "drop", "wind", "snowflake", "thermometer", "chart.line.uptrend.xyaxis", "chart.pie", "tablecells",
        "wallet.pass", "briefcase", "building.2", "storefront", "truck.box", "bicycle", "bus", "tram", "trophy", "crown",
        "sparkles", "paintpalette", "paintbrush", "ruler", "safari", "lightbulb", "power", "archivebox", "tray", "shippingbox",
        "square.3.layers.3d", "folder.badge.plus", "doc.badge.plus", "book", "book.closed", "newspaper", "graduationcap", "tv", "radio", "gamecontroller",
        "puzzlepiece", "waveform.path.ecg", "pills", "dog", "cat", "tree", "mountain.2", "wrench", "hammer", "person.2",
        "person.badge.plus", "face.smiling", "hand.raised", "hand.thumbsdown", "cursorarrow", "arrow.up.and.down.and.arrow.left.and.right", "arrow.up.left.and.arrow.down.right", "crop", "plus.magnifyingglass", "minus.magnifyingglass",
        "qrcode", "touchid", "xmark.square", "plus.square", "minus.square", "bell.badge", "star.leadinghalf.filled", "arrow.up.right", "arrow.down.left", "arrow.turn.up.left",
        "repeat", "shuffle", "backward.fill", "forward.fill", "speaker.slash", "speaker.wave.1", "forward.end.fill", "backward.end.fill", "sidebar.right", "rectangle.split.3x1",
        "link.badge.plus", "eraser", "highlighter", "eyedropper", "hexagon", "pentagon", "seal", "star.circle", "heart.circle", "trash.circle",
    ]

    /// The catalog laid out at one font, weight and image scale; the probes are the symbol names.
    private static func catalog(_ name: String, font: Font, weight: Font.Weight? = nil, scale: Image.Scale = .medium) -> Fixture {
        Fixture("symbol/catalog-\(name)", size: CGSize(width: 560, height: 1000)) {
            VStack(spacing: 4) {
                ForEach(Array(stride(from: 0, to: catalogNames.count, by: 10)), id: \.self) { start in
                    // A text on the row's baseline gives each symbol's descent below the baseline.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Star").probe("row\(start)")
                        ForEach(catalogNames[start..<min(start + 10, catalogNames.count)], id: \.self) { name in
                            Image(systemName: name).probe(name)
                        }
                    }
                }
            }
            .font(font)
            .fontWeight(weight)
            .imageScale(scale)
            .probe("grid")
        }
    }

    /// One catalog per macOS text-style size at the regular weight (10 caption, 11 subheadline,
    /// 12 callout, 13 body, 15 title3, 17 title2, 22 title, 26 largeTitle), plus the body size in
    /// semibold and bold and at the small and large image scales.
    public static let catalogs: [Fixture] = [
        catalog("10", font: .system(size: 10)), catalog("11", font: .system(size: 11)), catalog("12", font: .system(size: 12)),
        catalog("13", font: .system(size: 13)), catalog("15", font: .system(size: 15)), catalog("17", font: .system(size: 17)),
        catalog("22", font: .system(size: 22)), catalog("26", font: .system(size: 26)),
        catalog("13-semibold", font: .system(size: 13), weight: .semibold), catalog("13-bold", font: .system(size: 13), weight: .bold),
        catalog("13-small", font: .system(size: 13), scale: .small), catalog("13-large", font: .system(size: 13), scale: .large),
    ]

    /// The rules; rows whose sizes are measured come first, the last row holds sizes the table
    /// can only scale to (Tier A allows them half a point).
    public static let basic = Fixture("symbol/basic", size: CGSize(width: 400, height: 420)) {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "star").probe("body")
                Image(systemName: "star").font(.caption).probe("caption")
                Image(systemName: "star").font(.title).probe("title")
                Image(systemName: "star").font(.largeTitle).probe("largeTitle")
                Image(systemName: "star").font(.system(size: 17)).probe("size17")
                Image(systemName: "star").font(.system(size: 11)).probe("size11")
            }
            HStack(spacing: 8) {
                Image(systemName: "star").imageScale(.small).probe("small")
                Image(systemName: "star").imageScale(.medium).probe("medium")
                Image(systemName: "star").imageScale(.large).probe("large")
                Image(systemName: "star").bold().probe("bold")
                Image(systemName: "star").fontWeight(.semibold).probe("semibold")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "star").probe("baselineIcon")
                Text("Star").probe("baselineText")
                Image(systemName: "star").font(.title).probe("baselineTitleIcon")
                Text("Star").font(.title).probe("baselineTitleText")
            }
            .probe("baselineRow")
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "star").probe("centerIcon")
                Text("Star").probe("centerText")
            }
            .probe("centerRow")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ForEach([10, 17, 26], id: \.self) { size in
                    Image(systemName: "star").font(.system(size: CGFloat(size))).probe("baselineIcon\(size)")
                    Text("Star").font(.system(size: CGFloat(size))).probe("baselineText\(size)")
                }
                Image(systemName: "star").imageScale(.large).probe("baselineLargeIcon")
                Image(systemName: "star").bold().probe("baselineBoldIcon")
                Image(systemName: "rectangle.portrait").probe("baselineTallIcon")
                Image(systemName: "ellipsis").probe("baselineFlatIcon")
                Text("Star").probe("baselineText2")
            }
            .probe("baselineRow2")
            Label { Text("Star label").probe("labelText") } icon: { Image(systemName: "star").probe("labelIcon") }.probe("label")
            Label { Text("Star label").probe("labelTitleText") } icon: { Image(systemName: "star").probe("labelTitleIcon") }.font(.title).probe("labelTitle")
            Label { Text("Star label").probe("labelBodyText") } icon: { Image(systemName: "star").probe("labelBodyIcon") }.font(.body).probe("labelBody")
            Label { Text("Star label").probe("labelImageText") } icon: { Image("icon").probe("labelImageIcon") }.probe("labelImage")
            Button { } label: { Label("Star button", systemImage: "star") }.probe("button")
            HStack(spacing: 8) {
                Image(systemName: "star").resizable().frame(width: 50, height: 50).probe("resizable")
                Image(systemName: "star").resizable().scaledToFit().frame(width: 50, height: 30).probe("fit")
                Image(systemName: "star.fill").foregroundStyle(.red).probe("red")
                Image(systemName: "chevron.right").probe("chevron")
                Image(systemName: "not.a.symbol.name").probe("unknown")
                Image(systemName: "line.3.horizontal").probe("wide")
                Image(systemName: "rectangle.portrait").probe("tall")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "star").font(.system(size: 24)).probe("size24")
                Image(systemName: "star").font(.system(size: 40)).probe("size40")
                Text("Star").font(.system(size: 40)).probe("baselineText40")
                Image(systemName: "star").font(.system(size: 24)).imageScale(.large).probe("largeSize24")
                Image(systemName: "star").fontWeight(.light).probe("light")
                Image(systemName: "star").fontWeight(.black).probe("black")
                Image(systemName: "star.fill").foregroundColor(.blue).font(.system(size: 30)).probe("blue30")
                Image(systemName: "chevron.right").font(.system(size: 30, weight: .semibold)).probe("chevronSemibold")
            }
            .probe("approximateRow")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .probe("stack")
    }

    public static let all: [Fixture] = catalogs + [basic]
}
