/// String-independent metrics of the macOS system font as SwiftUI lays text out, measured from
/// `Fixtures/Goldens/text-metrics.json` (`fonts`, 2026-09-02). Text styles carry their own
/// leading; point-size fonts use a different, tighter table. Engines that can only measure
/// widths (Canvas) take line heights, baselines and spacing from here; sizes between measured
/// points are interpolated and flagged approximate in the support matrix.
public struct SystemFontMetrics: Sendable, Equatable {
    public var lineHeight: CGFloat
    public var baseline: CGFloat
    public var spacingBelow: CGFloat
    public var spacingAbove: CGFloat
    public var textToText: CGFloat

    public init(lineHeight: CGFloat, baseline: CGFloat, spacingBelow: CGFloat, spacingAbove: CGFloat, textToText: CGFloat) {
        self.lineHeight = lineHeight
        self.baseline = baseline
        self.spacingBelow = spacingBelow
        self.spacingAbove = spacingAbove
        self.textToText = textToText
    }

    public var fontMetrics: FontMetrics {
        FontMetrics(lineHeight: lineHeight, spacingBelow: spacingBelow, spacingAbove: spacingAbove, textToText: textToText)
    }
}

extension PlatformProfile {
    /// Measured per text style (weight and design variants share the style's values).
    package static let macOSTextStyleMetrics: [Font.TextStyle: SystemFontMetrics] = [
        .largeTitle: .init(lineHeight: 38, baseline: 29, spacingBelow: 23.3017578125, spacingAbove: 12.678809606772006, textToText: 1.5),
        .title: .init(lineHeight: 33, baseline: 25, spacingBelow: 20.9091796875, spacingAbove: 11.092013651473215, textToText: 0.5),
        .title2: .init(lineHeight: 25.5, baseline: 19, spacingBelow: 16.04345703125, spacingAbove: 8.772221650828256, textToText: 2),
        .title3: .init(lineHeight: 22, baseline: 17, spacingBelow: 13.59716796875, spacingAbove: 7.498116357181818, textToText: 2.5),
        .headline: .init(lineHeight: 18.5, baseline: 14, spacingBelow: 11.15087890625, spacingAbove: 6.273261859394714, textToText: 1),
        .subheadline: .init(lineHeight: 16, baseline: 12, spacingBelow: 10.20458984375, spacingAbove: 5.680712890625, textToText: 1.5),
        .body: .init(lineHeight: 18.5, baseline: 14, spacingBelow: 11.15087890625, spacingAbove: 6.2240598101696385, textToText: 1),
        .callout: .init(lineHeight: 17.5, baseline: 13, spacingBelow: 10.67773437500, spacingAbove: 5.952392578125, textToText: 1),
        .footnote: .init(lineHeight: 15, baseline: 11, spacingBelow: 9.23144531250, spacingAbove: 4.909019062500, textToText: 1.5),
        .caption: .init(lineHeight: 15, baseline: 11, spacingBelow: 9.23144531250, spacingAbove: 4.909019062500, textToText: 1.5),
        .caption2: .init(lineHeight: 15, baseline: 11, spacingBelow: 9.23144531250, spacingAbove: 4.9146757604505495, textToText: 1.5),
    ]

    /// Measured point-size fonts (`Font.system(size:)`), keyed by size.
    package static let macOSPointSizeMetrics: [(size: CGFloat, metrics: SystemFontMetrics)] = [
        (10, .init(lineHeight: 13, baseline: 10, spacingBelow: 6.23144531250, spacingAbove: 3.609375, textToText: 0)),
        (12, .init(lineHeight: 15, baseline: 12, spacingBelow: 7.17773437500, spacingAbove: 4.03125, textToText: 0)),
        (13, .init(lineHeight: 16, baseline: 13, spacingBelow: 7.65136718750, spacingAbove: 4.2421875, textToText: 0)),
        (20, .init(lineHeight: 24, baseline: 19, spacingBelow: 11.96289062500, spacingAbove: 6.71875, textToText: 0)),
        (24, .init(lineHeight: 28, baseline: 23, spacingBelow: 14.35546875000, spacingAbove: 8.0625, textToText: 0)),
        (32, .init(lineHeight: 38, baseline: 31, spacingBelow: 19.14062500000, spacingAbove: 10.75, textToText: 0)),
    ]

    /// Metrics for a resolved font; interpolated for unmeasured point sizes.
    public func systemFontMetrics(for font: ResolvedFont) -> SystemFontMetrics {
        if let style = font.textStyle, let metrics = Self.macOSTextStyleMetrics[style] {
            return metrics
        }
        let table = Self.macOSPointSizeMetrics
        if let exact = table.first(where: { $0.size == font.size }) { return exact.metrics }
        guard let lower = table.last(where: { $0.size < font.size }), let upper = table.first(where: { $0.size > font.size }) else {
            // Outside the measured range: scale the nearest entry.
            let nearest = font.size < table[0].size ? table[0] : table[table.count - 1]
            let ratio = font.size / nearest.size
            let m = nearest.metrics
            return SystemFontMetrics(lineHeight: (m.lineHeight * ratio).rounded(), baseline: (m.baseline * ratio).rounded(),
                                     spacingBelow: m.spacingBelow * ratio, spacingAbove: m.spacingAbove * ratio, textToText: 0)
        }
        let t = (font.size - lower.size) / (upper.size - lower.size)
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        let a = lower.metrics, b = upper.metrics
        return SystemFontMetrics(lineHeight: lerp(a.lineHeight, b.lineHeight).rounded(), baseline: lerp(a.baseline, b.baseline).rounded(),
                                 spacingBelow: lerp(a.spacingBelow, b.spacingBelow), spacingAbove: lerp(a.spacingAbove, b.spacingAbove), textToText: 0)
    }
}
