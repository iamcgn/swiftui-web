// Shared between the Apple harness and SwiftUIWeb: every (string, font, width) that text
// fixtures use. GoldenGen measures each with real SwiftUI and writes Fixtures/Goldens/text-metrics.json;
// the headless text engine replays those numbers so Tier A layout stays exact.
import SwiftUI

/// A font spelled in a toolchain-neutral way. `key` must match `ResolvedFont.key` in SwiftUIWebCore.
public enum FixtureFont: Hashable, Sendable {
    case style(String, weight: String? = nil, design: String? = nil, italic: Bool = false)   // "body", "title", … with optional overrides
    case system(size: CGFloat, weight: String, design: String, italic: Bool = false)          // weight "regular"…"black", design "default"…

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
        case .style(let name, let weight, let design, let italic):
            var key = "style:\(name)"
            if let weight { key += ":w\(Self.weights[weight]!.1)" }
            if let design, design != "default" { key += ":\(design)" }
            return key + (italic ? ":italic" : "")
        case .system(let size, let weight, let design, let italic):
            let sizeText = size == size.rounded() ? "\(Int(size))" : "\(size)"
            return "system:\(sizeText):\(Self.weights[weight]!.1):\(design)" + (italic ? ":italic" : "")
        }
    }

    public var font: Font {
        switch self {
        case .style(let name, let weight, let design, let italic):
            let font = Font.system(Self.styles[name]!, design: Self.design(design), weight: weight.map { Self.weights[$0]!.0 })
            return italic ? font.italic() : font
        case .system(let size, let weight, let design, let italic):
            let font = Font.system(size: size, weight: Self.weights[weight]!.0, design: Self.design(design) ?? .default)
            return italic ? font.italic() : font
        }
    }
}

/// Layout options a text is measured with (`lineLimit`, `truncationMode`, `lineSpacing`).
/// Spelled into the key exactly like `TextLayoutOptions` in SwiftUIWebCore (`TextMetricsKey`).
public struct TextMetricOptions: Hashable, Sendable {
    public var lineLimit: Int? = nil
    /// Reserved lines: `lineLimit(n, reservesSpace: true)` when equal to `lineLimit`, otherwise
    /// the lower bound of a range limit.
    public var minimumLines = 0
    public var lineSpacing: CGFloat = 0
    public var truncation = "tail"      // "head" | "middle" | "tail"

    public init(lineLimit: Int? = nil, minimumLines: Int = 0, lineSpacing: CGFloat = 0, truncation: String = "tail") {
        self.lineLimit = lineLimit
        self.minimumLines = minimumLines
        self.lineSpacing = lineSpacing
        self.truncation = truncation
    }

    public static let `default` = TextMetricOptions()

    /// The suffix appended to the width slot of a key.
    public var keySuffix: String {
        var suffix = ""
        if let lineLimit { suffix += ";l\(lineLimit)" }
        if minimumLines > 0 { suffix += ";r\(minimumLines)" }
        if lineSpacing != 0 { suffix += ";s\(lineSpacing)" }
        if truncation != "tail" { suffix += ";t\(truncation)" }
        return suffix
    }
}

public struct TextMetricRequest: Hashable, Sendable {
    /// One part of a concatenated text: a string in a font.
    public struct Run: Hashable, Sendable {
        public let string: String
        public let font: FixtureFont
        public init(_ string: String, _ font: FixtureFont) {
            self.string = string
            self.font = font
        }
    }

    public let runs: [Run]
    public let width: CGFloat?
    public let options: TextMetricOptions

    public init(_ string: String, _ font: FixtureFont, width: CGFloat? = nil, options: TextMetricOptions = .default) {
        self.runs = [Run(string, font)]
        self.width = width
        self.options = options
    }

    /// A mixed-font text (`Text("a").font(f1) + Text("b").font(f2)`).
    public init(runs: [Run], width: CGFloat? = nil, options: TextMetricOptions = .default) {
        self.runs = runs
        self.width = width
        self.options = options
    }

    public var string: String { runs.map(\.string).joined() }
    /// The fonts the request uses (one per run, in order).
    public var fonts: [FixtureFont] { runs.map(\.font) }

    /// Adjacent runs in the same font, merged: colour boundaries do not affect measurement.
    public var mergedRuns: [Run] {
        var merged: [Run] = []
        for run in runs {
            if let last = merged.last, last.font == run.font {
                merged[merged.count - 1] = Run(last.string + run.string, run.font)
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// Key in text-metrics.json: `<font>|<width><options>|<string>`, with `rich:<key>=<count>,…`
    /// as the font of a mixed-font text (see `TextMetricsKey` in SwiftUIWebCore).
    public var key: String {
        let merged = mergedRuns
        let fontSlot = merged.count == 1 ? merged[0].font.key : "rich:" + merged.map { "\($0.font.key)=\($0.string.count)" }.joined(separator: ",")
        return "\(fontSlot)|\(width.map { "\($0)" } ?? "")\(options.keySuffix)|\(string)"
    }
}

public enum TextMetricsRequests {
    /// The font text gets when nothing sets one: on macOS the 13 pt system font (16 pt line), not
    /// `.body` (18.5 pt line) — see decision 0010.
    public static let defaultFont = FixtureFont.system(size: 13, weight: "regular", design: "default")
    static func defaultFont(weight: String) -> FixtureFont { .system(size: 13, weight: weight, design: "default") }

    public static let styleNames = ["largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "footnote", "caption", "caption2"]
    public static let sample = "The quick brown fox"
    public static let paragraph = "Layout must wrap this sentence onto several lines inside a narrow frame."
    /// Two paragraphs separated by a hard line break.
    public static let twoParagraphs = "First line.\nSecond paragraph wraps here as well."
    public static let newlineShort = "Left\nRight side"
    public static let longWord = "Supercalifragilistic"
    /// Parts of the mixed-font concatenations in text/concatenation.
    public static let richParagraphHead = "Layout must "
    public static let richParagraphTail = "wrap this sentence onto several lines inside a narrow frame."

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
            TextMetricRequest("OK", .style("body")),
            TextMetricRequest("Increment", .style("body")),
            TextMetricRequest("Label", .style("body")),
            TextMetricRequest("−", .style("body")),
            TextMetricRequest("+", .style("body")),
            TextMetricRequest("Plain", .style("body")),
            TextMetricRequest("Bordered", .style("body")),
            TextMetricRequest("Borderless", .style("body")),
            TextMetricRequest("Prominent", .style("body")),
            TextMetricRequest("Padded", .style("body")),
            TextMetricRequest("Count: 0", .system(size: 13, weight: "regular", design: "default")),
            TextMetricRequest("Hg", .style("largeTitle")),
            TextMetricRequest("Hg", .style("caption2")),
        ]
        for style in styleNames { requests.append(TextMetricRequest(sample, .style(style))) }
        // Strings that fixtures show in the default font (layout, paint, button, ForEach, Section).
        for word in ["Hello", "One", "Two", "Three", "small", "Env", "Count: 0", "Hg", "OK", "Increment", "Label", "−", "+",
                     "Plain", "Bordered", "Borderless", "Prominent", "Padded",
                     "Row 0", "Row 1", "Row 2", "Apple", "Banana", "Cherry", "Alpha", "Beta", "Gamma", "Fruits",
                     "Vegetables", "Carrot", "Leek", "Header", "Footer", "Top", "Bottom", "A", "B"] {
            requests.append(TextMetricRequest(word, defaultFont))
        }
        requests.append(TextMetricRequest(paragraph, defaultFont))
        for width: CGFloat in [150, 260, 400] { requests.append(TextMetricRequest(paragraph, defaultFont, width: width)) }
        for weight in ["semibold", "bold", "heavy"] { requests.append(TextMetricRequest("Bold", defaultFont(weight: weight))) }
        requests.append(TextMetricRequest("Weight", defaultFont(weight: "semibold")))
        // Bold trait per text style (text/bold-trait): record the candidate weights.
        for style in styleNames {
            for weight in ["medium", "semibold", "bold", "heavy"] { requests.append(TextMetricRequest("Bold", .style(style, weight: weight))) }
        }
        requests.append(TextMetricRequest("Bold", .system(size: 20, weight: "bold", design: "default")))
        // Section headers, should they turn out to be styled outside List/Form.
        for word in ["Fruits", "Vegetables", "Header"] {
            requests.append(TextMetricRequest(word, .style("headline")))
        }
        // Bordered button labels use the 13 pt point-size font.
        for label in ["OK", "Increment", "Label", "−", "+", "Bordered", "Prominent", "Padded", "Go"] {
            requests.append(TextMetricRequest(label, .system(size: 13, weight: "regular", design: "default")))
        }
        for size: CGFloat in [10, 12, 20, 24, 32] { requests.append(TextMetricRequest(sample, .system(size: size, weight: "regular", design: "default"))) }
        for weight in ["light", "medium", "bold", "black"] { requests.append(TextMetricRequest(sample, .system(size: 20, weight: weight, design: "default"))) }
        for design in ["rounded", "serif", "monospaced"] { requests.append(TextMetricRequest(sample, .system(size: 20, weight: "regular", design: design))) }

        // Text completeness (Phase 2): wrapped paragraphs, line limit, truncation, spacing, concatenation.
        for width: CGFloat in [100, 120, 134, 200, 300] { requests.append(TextMetricRequest(paragraph, defaultFont, width: width)) }
        for limit in [1, 2, 3, 10] { requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: limit))) }
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 260, options: .init(lineLimit: 1)))
        for mode in ["head", "middle"] { requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 1, truncation: mode))) }
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 2, truncation: "middle")))
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 3, minimumLines: 1)))
        for spacing: CGFloat in [4, 10] { requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineSpacing: spacing))) }
        requests.append(TextMetricRequest(paragraph, .style("body"), width: 150, options: .init(lineSpacing: 4)))
        requests.append(TextMetricRequest(paragraph, .style("title"), width: 300))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineLimit: 1)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineLimit: 2, minimumLines: 2)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineLimit: 4, minimumLines: 2)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(minimumLines: 3)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineSpacing: 10)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(truncation: "head")))
        requests.append(TextMetricRequest(twoParagraphs, defaultFont))
        requests.append(TextMetricRequest(twoParagraphs, defaultFont, width: 220))
        requests.append(TextMetricRequest(newlineShort, defaultFont))
        requests.append(TextMetricRequest(longWord, defaultFont, width: 60))
        requests.append(TextMetricRequest(longWord, defaultFont))
        // Toggle and Label fixtures (default font and, should the controls style their labels, body).
        for word in ["Enabled", "Title", "On", "Off", "Placeholder", "Name", "Password", "A", "B"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("body")))
        }
        // Sidebar list rows use the body font.
        for word in ["Apple", "Banana", "Cherry"] { requests.append(TextMetricRequest(word, .style("body"))) }
        // List section headers and footers: candidate styles and weights.
        for word in ["Fruits", "Vegetables", "Footer"] {
            for style in ["headline", "subheadline", "footnote", "caption", "caption2", "body"] {
                for weight in ["regular", "medium", "semibold", "bold"] {
                    requests.append(TextMetricRequest(word, .style(style, weight: weight)))
                }
            }
            for size: CGFloat in [11, 12] {
                for weight in ["regular", "medium", "semibold", "bold"] {
                    requests.append(TextMetricRequest(word, .system(size: size, weight: weight, design: "default")))
                }
            }
        }
        // NavigationLink labels: default font, the 13 pt point-size font of bordered buttons, body.
        for word in ["Root", "Detail", "Value", "Wide", "Push", "Deeper", "Content", "Small", "Left", "Right", "Apple detail",
                     "Number 1", "Number 2", "Number 3", "Go"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
            requests.append(TextMetricRequest(word, .style("body")))
        }
        // Picker, Slider and Stepper labels and options: candidate fonts for control text.
        for word in ["Fruit", "Volume", "Min", "Max", "Count", "Row", "0", "1", "2", "25", "50", "75", "100"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("body")))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        for word in ["Apple", "Banana", "Cherry", "Fruit", "Min", "Max"] {
            for style in ["callout", "footnote", "caption", "caption2", "subheadline"] {
                requests.append(TextMetricRequest(word, .style(style)))
                for weight in ["regular", "medium", "semibold"] { requests.append(TextMetricRequest(word, .style(style, weight: weight))) }
            }
            for size: CGFloat in [10, 11, 12, 13] {
                for weight in ["regular", "medium", "semibold"] { requests.append(TextMetricRequest(word, .system(size: size, weight: weight, design: "default"))) }
            }
        }
        // Form rows, headers and footers.
        for word in ["Name", "Enabled", "Fruit", "Volume", "Count", "Save", "Plain", "Hello", "Account", "Options", "Footer"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("body")))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
            for style in ["headline", "subheadline", "footnote", "caption", "callout", "title3"] {
                requests.append(TextMetricRequest(word, .style(style)))
                for weight in ["medium", "semibold", "bold"] { requests.append(TextMetricRequest(word, .style(style, weight: weight))) }
            }
        }
        // Lifecycle fixtures.
        for word in ["A0 D0", "A1 D0", "A1 D1", "A2 D1", "A2 D2", "Child", "Waiting", "Done"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Above", "Below"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Sheet", "Popover", "Alert", "Done", "OK", "Sheet content", "Popover content", "Alert title", "Message"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        for word in ["One", "Two", "Three", "Four", "Five", "Six", "A", "B", "D", "E", "Low", "High", "Last"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["BB", "CCC", "F", "G", "H", "Header"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Canvas", "Corner"] { requests.append(TextMetricRequest(word, defaultFont)); requests.append(TextMetricRequest(word, defaultFont, width: 100)) }
        for word in ["Count: 0", "Count: 1", "Count: 2", "Flag"] { requests.append(TextMetricRequest(word, defaultFont)); requests.append(TextMetricRequest(word, .style("body"))) }
        for word in ["Ticks: 0", "Ticks: 1", "Live", "Slow"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Email", "Focused: none", "Focused: name", "Focused: email", "Focus email"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        for word in ["Heading", "Plain", "Secret", "Card", "Detail", "Save"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        requests.append(TextMetricRequest("Tilt", defaultFont))
        requests.append(TextMetricRequest("Sky", defaultFont))
        requests.append(TextMetricRequest("First", defaultFont))
        requests.append(TextMetricRequest("Second", defaultFont))
        requests.append(TextMetricRequest("One", defaultFont))
        requests.append(TextMetricRequest("Two", defaultFont))
        requests.append(TextMetricRequest("Three", defaultFont))
        requests.append(TextMetricRequest("A", defaultFont))
        requests.append(TextMetricRequest("B", defaultFont))
        requests.append(TextMetricRequest("No Mail", defaultFont))
        requests.append(TextMetricRequest("Try again later.", defaultFont))
        requests.append(TextMetricRequest("No Results", defaultFont))
        requests.append(TextMetricRequest("Search again.", defaultFont))
        requests.append(TextMetricRequest("Retry", defaultFont))
        requests.append(TextMetricRequest("Share", defaultFont))
        requests.append(TextMetricRequest("Send", defaultFont))
        requests.append(TextMetricRequest("Share…", defaultFont))
        requests.append(TextMetricRequest("No Mail", .style("largeTitle", weight: "bold")))
        requests.append(TextMetricRequest("No Results", .style("largeTitle", weight: "bold")))
        requests.append(TextMetricRequest("Try again later.", .style("body")))
        requests.append(TextMetricRequest("Search again.", .style("body")))
        requests.append(TextMetricRequest("Check the spelling or try a new search.", .style("body")))
        requests.append(TextMetricRequest("Check the spelling or try a new search.", defaultFont))
        requests.append(TextMetricRequest("Details", defaultFont))
        requests.append(TextMetricRequest("Alpha", defaultFont))
        requests.append(TextMetricRequest("Beta", defaultFont))
        requests.append(TextMetricRequest("Header", defaultFont))
        requests.append(TextMetricRequest("Hi", defaultFont))
        for word in ["Menu", "Select"] { requests.append(TextMetricRequest(word, defaultFont)) }
        requests.append(TextMetricRequest("Details", .style("body")))
        requests.append(TextMetricRequest("Outer", .style("body")))
        requests.append(TextMetricRequest("Inner", .style("body")))
        requests.append(TextMetricRequest("Header", .style("headline")))
        requests.append(TextMetricRequest("Name", defaultFont))
        requests.append(TextMetricRequest("Corey", defaultFont))
        requests.append(TextMetricRequest("Count", defaultFont))
        requests.append(TextMetricRequest("3", defaultFont))
        requests.append(TextMetricRequest("Network", defaultFont))
        requests.append(TextMetricRequest("Hidden", defaultFont))
        requests.append(TextMetricRequest("Shown", defaultFont))
        requests.append(TextMetricRequest("Toggle", defaultFont))
        requests.append(TextMetricRequest("Narrow", defaultFont))
        requests.append(TextMetricRequest("Value", defaultFont))
        requests.append(TextMetricRequest("Email", defaultFont))
        requests.append(TextMetricRequest("Apple", defaultFont))
        requests.append(TextMetricRequest("Open site", defaultFont))
        requests.append(TextMetricRequest("Visit", defaultFont))
        requests.append(TextMetricRequest("the site", defaultFont))
        requests.append(TextMetricRequest("Disabled", defaultFont))
        requests.append(TextMetricRequest("Large", .style("title")))
        requests.append(TextMetricRequest("Name", .style("body")))
        requests.append(TextMetricRequest("Network", .style("body")))
        requests.append(TextMetricRequest("Narrow", .style("body")))
        requests.append(TextMetricRequest("Wide", .style("body")))
        requests.append(TextMetricRequest("Toggle", .style("body")))
        requests.append(TextMetricRequest("Hidden", .style("body")))
        requests.append(TextMetricRequest("Count", .style("body")))
        requests.append(TextMetricRequest("Email", .style("body")))
        requests.append(TextMetricRequest("Settings", defaultFont))
        requests.append(TextMetricRequest("Inside", defaultFont))
        requests.append(TextMetricRequest("Option", defaultFont))
        requests.append(TextMetricRequest("Plain content", defaultFont))
        requests.append(TextMetricRequest("Custom", defaultFont))
        requests.append(TextMetricRequest("Wide", defaultFont))
        requests.append(TextMetricRequest("Outer", defaultFont))
        requests.append(TextMetricRequest("Inner", defaultFont))
        requests.append(TextMetricRequest("Nested", defaultFont))
        requests.append(TextMetricRequest("Settings", .style("subheadline")))
        requests.append(TextMetricRequest("Wide", .style("subheadline")))
        requests.append(TextMetricRequest("Outer", .style("subheadline")))
        requests.append(TextMetricRequest("Inner", .style("subheadline")))
        requests.append(TextMetricRequest("Option", .style("body")))
        requests.append(TextMetricRequest("Custom", .style("subheadline")))
        requests.append(TextMetricRequest("Loading", defaultFont))
        requests.append(TextMetricRequest("Copying", defaultFont))
        requests.append(TextMetricRequest("30%", defaultFont))
        requests.append(TextMetricRequest("Ring", defaultFont))
        requests.append(TextMetricRequest("Working", defaultFont))
        requests.append(TextMetricRequest("Focus me", defaultFont))
        requests.append(TextMetricRequest("Save", defaultFont))
        requests.append(TextMetricRequest("Go", defaultFont))
        requests.append(TextMetricRequest("Cancel", defaultFont))
        requests.append(TextMetricRequest("Log: none", defaultFont))
        requests.append(TextMetricRequest("Selected: none", defaultFont))
        requests.append(TextMetricRequest("Star", defaultFont))
        requests.append(TextMetricRequest("Star label", defaultFont))
        requests.append(TextMetricRequest("Star button", defaultFont))
        requests.append(TextMetricRequest("Star", .style("title")))
        requests.append(TextMetricRequest("Star label", .style("title")))
        requests.append(TextMetricRequest("Gradient", .style("largeTitle")))
        requests.append(TextMetricRequest("Star label", .style("body")))
        requests.append(TextMetricRequest("Star", .system(size: 11, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 12, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 15, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 22, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 13, weight: "semibold", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 13, weight: "bold", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 10, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 17, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 26, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 40, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Options", defaultFont))
        requests.append(TextMetricRequest("Custom", defaultFont))
        requests.append(TextMetricRequest("Primary", defaultFont))
        requests.append(TextMetricRequest("Plain", defaultFont))
        requests.append(TextMetricRequest("Hidden", defaultFont))
        requests.append(TextMetricRequest("Right-click me", defaultFont))
        requests.append(TextMetricRequest("Last: none 0", defaultFont))
        requests.append(TextMetricRequest("Cut", defaultFont))
        requests.append(TextMetricRequest("Copy", defaultFont))
        requests.append(TextMetricRequest("More", defaultFont))
        requests.append(TextMetricRequest("Paste", defaultFont))
        requests.append(TextMetricRequest("Delete", defaultFont))
        requests.append(TextMetricRequest("Action", defaultFont))
        requests.append(TextMetricRequest("Hi", defaultFont))
        requests.append(TextMetricRequest("End", .style("largeTitle")))
        let bold13 = defaultFont(weight: "bold")
        requests.append(TextMetricRequest(runs: [.init("Hello, ", bold13), .init("World", defaultFont)]))
        requests.append(TextMetricRequest(runs: [.init("Big ", .style("largeTitle")), .init("small", defaultFont)]))
        requests.append(TextMetricRequest("Red Blue", defaultFont))
        requests.append(TextMetricRequest(runs: [.init("Title ", .style("title")), .init("italic", .style("title", italic: true))]))
        requests.append(TextMetricRequest(runs: [.init("Env ", .style("title")), .init("bold", .style("title", weight: "bold"))]))
        requests.append(TextMetricRequest(runs: [.init(richParagraphHead, bold13), .init(richParagraphTail, defaultFont)], width: 150))
        requests.append(TextMetricRequest(runs: [.init(richParagraphHead, bold13), .init(richParagraphTail, defaultFont)]))
        return requests
    }()
}
