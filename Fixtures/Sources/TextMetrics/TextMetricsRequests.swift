// Shared between the Apple harness and SwiftUIWeb: every (string, font, width) that text
// fixtures use. GoldenGen measures each with real SwiftUI and writes Fixtures/Goldens/text-metrics.json;
// the headless text engine replays those numbers so Tier A layout stays exact.
import SwiftUI

/// A font spelled in a toolchain-neutral way. `key` must match `ResolvedFont.key` in SwiftUIWebCore.
public enum FixtureFont: Hashable, Sendable {
    case style(String, weight: String? = nil, design: String? = nil)   // "body", "title", … with optional overrides
    case system(size: CGFloat, weight: String, design: String)          // weight "regular"…"black", design "default"…

    public static let weights: [String: (Font.Weight, Int)] = [
        "ultraLight": (.ultraLight, 100), "thin": (.thin, 200), "light": (.light, 300), "regular": (.regular, 400),
        "medium": (.medium, 500), "semibold": (.semibold, 600), "bold": (.bold, 700), "heavy": (.heavy, 800), "black": (.black, 900),
    ]

    public static let styles: [String: Font.TextStyle] = [
        "largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3, "headline": .headline,
        "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote, "caption": .caption, "caption2": .caption2,
    ]

    static func design(_ name: String?) -> Font.Design? {
        switch name {
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        case nil, "default": return nil
        default: fatalError("unknown design \(name!)")
        }
    }

    public var key: String {
        switch self {
        case .style(let name, let weight, let design):
            var key = "style:\(name)"
            if let weight { key += ":w\(Self.weights[weight]!.1)" }
            if let design, design != "default" { key += ":\(design)" }
            return key
        case .system(let size, let weight, let design):
            let sizeText = size == size.rounded() ? "\(Int(size))" : "\(size)"
            return "system:\(sizeText):\(Self.weights[weight]!.1):\(design)"
        }
    }

    public var font: Font {
        switch self {
        case .style(let name, let weight, let design):
            return Font.system(Self.styles[name]!, design: Self.design(design), weight: weight.map { Self.weights[$0]!.0 })
        case .system(let size, let weight, let design):
            return Font.system(size: size, weight: Self.weights[weight]!.0, design: Self.design(design) ?? .default)
        }
    }
}

public struct TextMetricRequest: Hashable, Sendable {
    public let string: String
    public let font: FixtureFont
    public let width: CGFloat?

    public init(_ string: String, _ font: FixtureFont, width: CGFloat? = nil) {
        self.string = string
        self.font = font
        self.width = width
    }

    /// Key in text-metrics.json.
    public var key: String {
        "\(font.key)|\(width.map { "\($0)" } ?? "")|\(string)"
    }
}

public enum TextMetricsRequests {
    public static let styleNames = ["largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "footnote", "caption", "caption2"]
    public static let sample = "The quick brown fox"
    public static let paragraph = "Layout must wrap this sentence onto several lines inside a narrow frame."

    public static let all: [TextMetricRequest] = {
        var requests: [TextMetricRequest] = [
            TextMetricRequest("Hello", .style("body")),
            TextMetricRequest("One", .style("body")),
            TextMetricRequest("Two", .style("body")),
            TextMetricRequest("Three", .style("body")),
            TextMetricRequest("Big", .style("largeTitle")),
            TextMetricRequest("small", .style("body")),
            TextMetricRequest("Bold", .style("body", weight: "bold")),
            TextMetricRequest("Bold", .style("body", weight: "semibold")),
            TextMetricRequest("Bold", .style("body", weight: "heavy")),
            TextMetricRequest("Weight", .style("body", weight: "semibold")),
            TextMetricRequest("Env", .style("title")),
            TextMetricRequest("Count: 0", .style("title")),
            TextMetricRequest("Count: 0", .style("body")),
            TextMetricRequest(paragraph, .style("body"), width: 150),
            TextMetricRequest(paragraph, .style("body"), width: 260),
            TextMetricRequest(paragraph, .style("body"), width: 400),
            TextMetricRequest(paragraph, .style("body")),
            TextMetricRequest("Hg", .style("body")),
            TextMetricRequest("Hg", .style("largeTitle")),
            TextMetricRequest("Hg", .style("caption2")),
        ]
        for style in styleNames { requests.append(TextMetricRequest(sample, .style(style))) }
        for size: CGFloat in [10, 12, 20, 24, 32] { requests.append(TextMetricRequest(sample, .system(size: size, weight: "regular", design: "default"))) }
        for weight in ["light", "medium", "bold", "black"] { requests.append(TextMetricRequest(sample, .system(size: 20, weight: weight, design: "default"))) }
        for design in ["rounded", "serif", "monospaced"] { requests.append(TextMetricRequest(sample, .system(size: 20, weight: "regular", design: design))) }
        return requests
    }()
}
