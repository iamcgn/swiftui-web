// The layout size of a symbol image (Docs/elements/Image.md): measured sizes from
// SystemSymbolMetricsTable at the macOS text-style point sizes, 13 pt weights and image scales,
// scaled linearly for anything else.

package enum SystemSymbolMetrics {
    package struct Size: Equatable, Sendable {
        package var width: CGFloat
        package var height: CGFloat
        /// How far the frame's bottom sits below the text baseline.
        package var descent: CGFloat

        package init(width: CGFloat, height: CGFloat, descent: CGFloat) {
            self.width = width
            self.height = height
            self.descent = descent
        }
    }

    /// The measured star at 13 pt, the stand-in for symbols with a glyph but no measurement.
    package static let fallback = Size(width: 16.5, height: 16, descent: 3)

    private static let semiboldIndex = 8, boldIndex = 9, smallIndex = 10, largeIndex = 11, bodyIndex = 3

    /// The size of `name` at `pointSize`, `weight` and `scale`, or nil when the symbol was not
    /// measured. Exact at the measured variants; other sizes scale the nearest measured size at
    /// or below linearly, other weights and scales apply the 13 pt ratios, all to the half point.
    package static func size(named name: String, pointSize: CGFloat, weight: Font.Weight, scale: Image.Scale) -> Size? {
        guard let values = SystemSymbolMetricsTable.sizes[name], values.count >= 36 else { return nil }
        return size(values: values, pointSize: pointSize, weight: weight, scale: scale)
    }

    package static func size(values: [Double], pointSize: CGFloat, weight: Font.Weight, scale: Image.Scale) -> Size {
        func entry(_ index: Int) -> Size {
            Size(width: values[3 * index], height: values[3 * index + 1], descent: values[3 * index + 2])
        }
        let weightIndex: Int? = weight.value >= 700 ? boldIndex : weight.value >= 600 ? semiboldIndex : nil
        let lightWeight = weight.value < 400
        let scaleIndex: Int? = scale == .small ? smallIndex : scale == .large ? largeIndex : nil
        if pointSize == 13, !lightWeight {
            switch (weightIndex, scaleIndex) {
            case (nil, nil): return entry(bodyIndex)
            case (let w?, nil): return entry(w)
            case (nil, let s?): return entry(s)
            default: break
            }
        }
        let sizes = SystemSymbolMetricsTable.pointSizes
        let index = sizes.lastIndex(where: { $0 <= pointSize }) ?? 0
        let base = entry(index)
        let factor = pointSize / sizes[index]
        var width = base.width * factor, height = base.height * factor, descent = base.descent * factor
        let body = entry(bodyIndex)
        func apply(_ variant: Size, inverse: Bool = false) {
            guard body.width > 0, body.height > 0 else { return }
            let wr = variant.width / body.width, hr = variant.height / body.height
            width *= inverse ? 1 / wr : wr
            height *= inverse ? 1 / hr : hr
            descent += (variant.descent - body.descent) * factor * (inverse ? -1 : 1)
        }
        if let weightIndex { apply(entry(weightIndex)) } else if lightWeight { apply(entry(semiboldIndex), inverse: true) }
        if let scaleIndex { apply(entry(scaleIndex)) }
        func half(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
        return Size(width: half(width), height: half(height), descent: half(descent))
    }
}
