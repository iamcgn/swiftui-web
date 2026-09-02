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

    /// Key of a single-font, default-options recording (see `TextMetricsKey`).
    public static func key(font: ResolvedFont, width: CGFloat?, string: String) -> String {
        TextMetricsKey.make(runs: [StyledRun(string, font: font)], options: .default, width: width)
    }

    public func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let key = TextMetricsKey.make(runs: runs, options: options, width: width)
        if let exact = entries[key] {
            return layout(from: exact, runs: runs)
        }
        if let width {
            // A single-line recording that fits the proposed width needs no wrapping, and neither
            // a line limit nor truncation nor line spacing changes it (unless space is reserved).
            if !options.reservesSpace,
               let single = entries[TextMetricsKey.make(runs: runs, options: .default, width: nil)], single.width <= width {
                return layout(from: single, runs: runs)
            }
            // Below the minimum the layout is the zero-width one.
            if let minimum = entries[TextMetricsKey.make(runs: runs, options: options, width: 0)], width <= minimum.width {
                return layout(from: minimum, runs: runs)
            }
        }
        misses.append(key)
        return TextLayout(size: .zero, firstBaseline: 0, lastBaseline: 0, lines: [])
    }

    /// One line holding every run. Each run's fragment width comes from its own single-run
    /// recording when there is one (rich requests record their parts), so headless painting
    /// places the parts of a concatenation where the browser would.
    private func layout(from entry: Entry, runs: [StyledRun]) -> TextLayout {
        var widths: [CGFloat] = []
        if runs.count == 1 {
            widths = [entry.width]
        } else {
            for run in runs {
                widths.append(entries[Self.key(font: run.font, width: nil, string: run.string)].map { CGFloat($0.width) } ?? 0)
            }
        }
        var layout = TextLayout.singleLine(runs, size: CGSize(width: entry.width, height: entry.height),
                                           baseline: entry.firstBaseline, runWidths: widths)
        layout.lastBaseline = entry.lastBaseline
        return layout
    }
}
#endif
