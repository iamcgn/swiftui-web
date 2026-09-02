import SwiftUIWebCore
#if !os(WASI)
import Foundation

/// Replays text measurements recorded from Apple's SwiftUI (`Fixtures/Goldens/text-metrics.json`),
/// so headless layout of the fixture strings is exact (Tier A).
@MainActor
public final class RecordedTextEngine: TextEngine {
    public struct Entry: Decodable, Sendable {
        public let width: Double
        public let height: Double
        public let firstBaseline: Double
        public let lastBaseline: Double

        public init(width: Double, height: Double, firstBaseline: Double, lastBaseline: Double) {
            self.width = width
            self.height = height
            self.firstBaseline = firstBaseline
            self.lastBaseline = lastBaseline
        }
    }

    public struct FontEntry: Decodable, Sendable {
        public let lineHeight: Double
        public let spacingBelow: Double
        public let spacingAbove: Double
        public let textToText: Double

        public init(lineHeight: Double, spacingBelow: Double, spacingAbove: Double, textToText: Double) {
            self.lineHeight = lineHeight
            self.spacingBelow = spacingBelow
            self.spacingAbove = spacingAbove
            self.textToText = textToText
        }
    }

    private struct Document: Decodable {
        let entries: [String: Entry]
        let fonts: [String: FontEntry]
    }

    public private(set) var entries: [String: Entry]
    public private(set) var fonts: [String: FontEntry]

    /// Requests that had no recording; tests fail on these so drift is caught.
    public private(set) var misses: [String] = []

    public init(entries: [String: Entry], fonts: [String: FontEntry] = [:]) {
        self.entries = entries
        self.fonts = fonts
    }

    public convenience init(contentsOf url: URL) throws {
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        self.init(entries: document.entries, fonts: document.fonts)
    }

    public func metrics(for font: ResolvedFont) -> FontMetrics {
        guard let entry = fonts[font.key] else {
            misses.append("font:\(font.key)")
            return .plain
        }
        return FontMetrics(lineHeight: entry.lineHeight, spacingBelow: entry.spacingBelow,
                           spacingAbove: entry.spacingAbove, textToText: entry.textToText)
    }

    public static func key(font: ResolvedFont, width: CGFloat?, string: String) -> String {
        "\(font.key)|\(width.map { "\($0)" } ?? "")|\(string)"
    }

    public func layout(_ string: String, font: ResolvedFont, width: CGFloat?) -> TextLayout {
        if let exact = entries[Self.key(font: font, width: width, string: string)] {
            return layout(from: exact, string: string)
        }
        if let width {
            // A single-line recording that fits the proposed width needs no wrapping.
            if let single = entries[Self.key(font: font, width: nil, string: string)], single.width <= width {
                return layout(from: single, string: string)
            }
            // Below the minimum (widest word) the layout is the zero-width one.
            if let minimum = entries[Self.key(font: font, width: 0, string: string)], width <= minimum.width {
                return layout(from: minimum, string: string)
            }
        }
        misses.append(Self.key(font: font, width: width, string: string))
        return TextLayout(size: .zero, firstBaseline: 0, lastBaseline: 0, lines: [])
    }

    private func layout(from entry: Entry, string: String) -> TextLayout {
        TextLayout(
            size: CGSize(width: entry.width, height: entry.height),
            firstBaseline: entry.firstBaseline,
            lastBaseline: entry.lastBaseline,
            lines: [TextLayout.Line(range: string.startIndex..<string.endIndex, width: entry.width, baseline: entry.firstBaseline)])
    }
}
#endif
