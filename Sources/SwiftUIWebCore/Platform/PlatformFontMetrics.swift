// The platform profile's view of the measured font tables (WebGraphics/Text/FontMetricsTable.swift).

extension PlatformProfile {
    /// Decoration metrics of a resolved font (`SystemFontMetricsTables.textDecorationMetrics`).
    public func textDecorationMetrics(for font: ResolvedFont) -> TextDecorationMetrics {
        SystemFontMetricsTables.textDecorationMetrics(for: font)
    }

    /// Metrics for a resolved font from the tables of the platform it was resolved for
    /// (`SystemFontMetricsTables.systemFontMetrics`).
    public func systemFontMetrics(for font: ResolvedFont) -> SystemFontMetrics {
        SystemFontMetricsTables.systemFontMetrics(for: font)
    }
}
