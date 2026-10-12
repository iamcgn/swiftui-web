// The scales and the geometry: records become positions in a plot rectangle. The rules are
// measured from Apple's Charts on macOS 27 (`charts/*` goldens, Docs/elements/Charts.md): a
// nominal axis is bands in order of appearance with bars 70 % wide, a quantitative one a
// "nice" domain including zero with four intervals (more past 240 pt) of 1, 2, 2.5 or 5 ×
// 10ⁿ; the axis labels are 11 pt secondary text (12 on iOS), 4 pt after a tick on the x axis
// and after the plot on the trailing y axis, 5 below the plot; grid lines are 1 pt primary at
// 13 %, dashed 3/3 vertically and solid horizontally.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import WebGraphics

package enum _ScaleKind { case nominal, quantitative, temporal }

/// A tick: its value, the label text and its fraction along the axis (0 at the start).
package struct _Tick {
    package var value: _PlotValue
    package var label: String
    package var fraction: CGFloat
    /// A nominal tick spans a band: its start and end fractions.
    package var bandStart: CGFloat = 0
    package var bandEnd: CGFloat = 0
}

/// One axis's scale: its kind, categories or domain, and ticks.
package struct _Scale {
    package var kind: _ScaleKind = .quantitative
    package var categories: [String] = []
    package var domain: ClosedRange<Double> = 0...1
    package var unit: Calendar.Component?
    package var ticks: [_Tick] = []
    package var customValues: [_PlotValue]?
    /// Nominal bands on the y axis run top to bottom.
    package var reversed = false

    package var isNominal: Bool { kind == .nominal }

    /// The fraction along the axis for a value: a band's centre, or the linear position.
    package func fraction(of value: _PlotValue) -> CGFloat? {
        switch kind {
        case .nominal:
            guard let category = value.category ?? value.continuous.map({ _formatNumber($0) }), let i = categories.firstIndex(of: category) else { return nil }
            let f = (CGFloat(i) + 0.5) / CGFloat(max(categories.count, 1))
            return reversed ? 1 - f : f
        case .quantitative, .temporal:
            guard let v = value.continuous else { return nil }
            let span = domain.upperBound - domain.lowerBound
            return span > 0 ? CGFloat((v - domain.lowerBound) / span) : 0.5
        }
    }

    /// A band's extent in fractions.
    package func band(of value: _PlotValue) -> ClosedRange<CGFloat>? {
        guard isNominal, let category = value.category, let i = categories.firstIndex(of: category) else { return nil }
        let n = CGFloat(max(categories.count, 1))
        return reversed ? (1 - CGFloat(i + 1) / n)...(1 - CGFloat(i) / n) : (CGFloat(i) / n)...(CGFloat(i + 1) / n)
    }

    package var bandFraction: CGFloat { isNominal ? 1 / CGFloat(max(categories.count, 1)) : 0 }

    /// The value at a fraction (for `ChartProxy.value(atX:)`).
    package func value(at fraction: CGFloat) -> _PlotValue? {
        switch kind {
        case .nominal:
            guard !categories.isEmpty else { return nil }
            let f = reversed ? 1 - fraction : fraction
            let i = min(max(Int(f * CGFloat(categories.count)), 0), categories.count - 1)
            return .category(categories[i])
        case .quantitative:
            return .number(domain.lowerBound + Double(fraction) * (domain.upperBound - domain.lowerBound))
        case .temporal:
            return .date(Date(timeIntervalSinceReferenceDate: domain.lowerBound + Double(fraction) * (domain.upperBound - domain.lowerBound)))
        }
    }
}

/// The chart's resolved data: records with stacking applied, the scales and the series.
package struct _ChartModel {
    package var records: [_MarkRecord] = []
    package var x = _Scale()
    package var y = _Scale()
    /// Legend entries in order of appearance with their styles.
    package var series: [(name: String, style: AnyShapeStyle)] = []
    package var seriesLabel: String?
    package var symbolsBySeries: [String: _SymbolShape] = [:]

    /// The categorical palette: the system colours in Swift Charts' order.
    package static let palette: [Color] = [.blue, .green, .orange, .purple, .red, .cyan, .yellow, .pink, .brown, .indigo, .mint, .teal]
    /// Marks without a series paint Swift Charts' own blue (0, 122, 255), not the system's.
    package static let defaultColor = Color(red: 0, green: 122 / 255, blue: 1)

    package init(records: [_MarkRecord], configuration: _ChartConfiguration) {
        self.records = records
        resolveSeries(configuration)
        stack()
        x = Self.makeScale(records: self.records, axis: .horizontal, configured: configuration.xDomain, marks: configuration.xAxis.marks)
        y = Self.makeScale(records: self.records, axis: .vertical, configured: configuration.yDomain, marks: configuration.yAxis.marks)
        y.reversed = y.isNominal
    }

    private mutating func resolveSeries(_ configuration: _ChartConfiguration) {
        var names: [String] = []
        for record in records {
            guard let s = record.series else { continue }
            if !names.contains(s) { names.append(s) }
            if seriesLabel == nil { seriesLabel = record.seriesLabel }
        }
        if let fixed = configuration.foregroundStyles {
            // The scale's order is the mapping's, with unmapped values after it.
            var ordered = fixed.map(\.0)
            for n in names where !ordered.contains(n) { ordered.append(n) }
            names = ordered
        }
        let palette = configuration.foregroundPalette ?? Self.palette.map { AnyShapeStyle($0) }
        for (i, name) in names.enumerated() {
            let style = configuration.foregroundStyles?.first { $0.0 == name }?.1 ?? palette[i % max(palette.count, 1)]
            series.append((name, style))
        }
        if let symbols = configuration.symbolScale {
            for (name, symbol) in symbols { symbolsBySeries[name] = symbol }
        }
        for i in records.indices where records[i].style == nil {
            if let s = records[i].series, let entry = series.first(where: { $0.name == s }) { records[i].style = entry.style }
            if let s = records[i].series, let symbol = symbolsBySeries[s] { records[i].symbol = symbol }
        }
    }

    /// Bars and areas sharing a position stack by their series (positive values up, negative
    /// down) unless dodged.
    private mutating func stack() {
        var positive: [String: Double] = [:]
        var negative: [String: Double] = [:]
        for i in records.indices {
            let r = records[i]
            guard r.kind == .bar || r.kind == .area, r.series != nil, r.dodge == nil else { continue }
            if let y = r.y?.number, r.yStart == nil, r.x != nil {
                let key = "x:" + r.x!.label
                if y >= 0 {
                    let start = positive[key] ?? 0
                    records[i].yStart = .number(start); records[i].yEnd = .number(start + y); positive[key] = start + y
                } else {
                    let start = negative[key] ?? 0
                    records[i].yStart = .number(start); records[i].yEnd = .number(start + y); negative[key] = start + y
                }
            } else if let x = r.x?.number, r.xStart == nil, r.y != nil, r.kind == .bar {
                let key = "y:" + r.y!.label
                if x >= 0 {
                    let start = positive[key] ?? 0
                    records[i].xStart = .number(start); records[i].xEnd = .number(start + x); positive[key] = start + x
                } else {
                    let start = negative[key] ?? 0
                    records[i].xStart = .number(start); records[i].xEnd = .number(start + x); negative[key] = start + x
                }
            }
        }
    }

    private static func makeScale(records: [_MarkRecord], axis: Axis, configured: _ScaleDomain?, marks: [AxisMarks]?) -> _Scale {
        var scale = _Scale()
        var values: [_PlotValue] = []
        var unit: Calendar.Component?
        var includesZero = false
        for r in records {
            let own: [_PlotValue?] = axis == .horizontal ? [r.x, r.xStart, r.xEnd] : [r.y, r.yStart, r.yEnd]
            values += own.compactMap { $0 }
            if axis == .horizontal, let u = r.xUnit { unit = u }
            if axis == .vertical, let u = r.yUnit { unit = u }
            // A quantitative scale includes zero (Swift Charts' default for every mark).
            includesZero = true
        }
        scale.unit = unit
        switch configured {
        case .categories(let c):
            scale.kind = .nominal; scale.categories = c
        case .numbers(let range):
            scale.kind = .quantitative; scale.domain = range
        case .dates(let range):
            scale.kind = .temporal; scale.domain = range.lowerBound.timeIntervalSinceReferenceDate...range.upperBound.timeIntervalSinceReferenceDate
        case nil:
            if values.contains(where: { $0.category != nil }) {
                scale.kind = .nominal
                for v in values { if let c = v.category, !scale.categories.contains(c) { scale.categories.append(c) } }
            } else if values.contains(where: { $0.date != nil }) {
                scale.kind = .temporal
                let seconds = values.compactMap(\.continuous)
                scale.domain = (seconds.min() ?? 0)...(seconds.max() ?? 1)
            } else {
                scale.kind = .quantitative
                let numbers = values.compactMap(\.number)
                var lo = numbers.min() ?? 0, hi = numbers.max() ?? 1
                if includesZero || numbers.isEmpty { lo = min(lo, 0); hi = max(hi, 0) }
                scale.domain = lo...hi
            }
        }
        if let m = marks?.first, case .values(let v) = m.values.kind { scale.customValues = v }
        return scale
    }

    /// Finalises a scale for an axis length: the nice domain and the ticks.
    package static func finish(_ scale: inout _Scale, length: CGFloat, marks: [AxisMarks]?, fixedDomain: Bool) {
        let values = marks?.first?.values.kind ?? .automatic(desiredCount: nil)
        switch scale.kind {
        case .nominal:
            scale.ticks = scale.categories.enumerated().map { i, c in
                let band = scale.band(of: .category(c)) ?? 0...1
                return _Tick(value: .category(c), label: c, fraction: scale.fraction(of: .category(c)) ?? 0, bandStart: band.lowerBound, bandEnd: band.upperBound)
            }
        case .quantitative:
            var lo = scale.domain.lowerBound, hi = scale.domain.upperBound
            var step: Double
            switch values {
            case .strideBy(let s): step = s
            case .values(let v):
                let numbers = v.compactMap(\.number)
                if !fixedDomain, let mn = numbers.min(), let mx = numbers.max() { lo = min(lo, mn); hi = max(hi, mx) }
                scale.domain = lo...hi
                scale.ticks = numbers.map { n in _Tick(value: .number(n), label: _formatNumber(n), fraction: scale.fraction(of: .number(n)) ?? 0) }
                return
            default:
                var desiredCount: Int?
                if case .automatic(let d) = values { desiredCount = d }
                let intervals = max(1, (desiredCount.map { $0 - 1 }) ?? min(max(Int(length / 60), 4), 10))
                let span = hi - lo
                step = span > 0 ? niceStep(span / Double(intervals)) : niceStep(max(abs(hi), 1) / Double(intervals))
            }
            if !fixedDomain {
                lo = (lo / step).rounded(.down) * step
                hi = (hi / step).rounded(.up) * step
                if hi == lo { hi = lo + step }
            }
            scale.domain = lo...hi
            var ticks: [_Tick] = []
            var v = (lo / step).rounded(.up) * step
            var guardCount = 0
            while v <= hi + step * 1e-9 && guardCount < 200 {
                let rounded = (v / step).rounded() * step
                ticks.append(_Tick(value: .number(rounded), label: _formatNumber(rounded), fraction: CGFloat((rounded - lo) / (hi - lo))))
                v += step
                guardCount += 1
            }
            scale.ticks = ticks
        case .temporal:
            let lo = scale.domain.lowerBound, hi = scale.domain.upperBound
            let span = hi - lo
            var component: Calendar.Component
            var count = 1
            if case .strideCalendar(let c, let n) = values { component = c; count = n }
            else if span >= 2 * 365 * 86400 { component = .year }
            else if span >= 60 * 86400 { component = .month }
            else if span >= 3 * 86400 { component = .day }
            else { component = .hour; count = span >= 86400 ? 6 : 1 }
            if case .values(let v) = values {
                scale.ticks = v.compactMap { value in
                    guard let d = value.date else { return nil }
                    return _Tick(value: value, label: _formatDate(d, unit: component), fraction: scale.fraction(of: value) ?? 0)
                }
                return
            }
            let calendar = Calendar.current
            var date = Date(timeIntervalSinceReferenceDate: lo)
            if let start = _unitStart(calendar, component, date) { date = start }
            var ticks: [_Tick] = []
            var guardCount = 0
            while date.timeIntervalSinceReferenceDate <= hi && guardCount < 400 {
                if date.timeIntervalSinceReferenceDate >= lo - 1 {
                    ticks.append(_Tick(value: .date(date), label: _formatDate(date, unit: component), fraction: scale.fraction(of: .date(date)) ?? 0))
                }
                guard let next = calendar.date(byAdding: component, value: count, to: date) else { break }
                date = next
                guardCount += 1
            }
            scale.ticks = ticks
        }
    }

    /// The nice step for a raw interval: 1, 2, 2.5 or 5 times a power of ten, the smallest at
    /// least the raw value.
    package static func niceStep(_ raw: Double) -> Double {
        guard raw > 0, raw.isFinite else { return 1 }
        let power = _pow(10, (_log(raw) / _log(10)).rounded(.down))
        let fraction = raw / power
        for candidate in [1.0, 2.0, 2.5, 5.0, 10.0] where candidate >= fraction - 1e-9 {
            return candidate * power
        }
        return 10 * power
    }
}

/// The plot's geometry for a size: the plot rectangle and the blocks around it.
package struct _ChartGeometry {
    package var plot: CGRect
    package var labelHeight: CGFloat
    package var xLabelsVisible: Bool
    package var yLabelsVisible: Bool
    package var yAxisLeading: Bool
    /// Nominal y labels are drawn inside the band's top (leading position).
    package var yLabelsInside: Bool

    package static let labelGap: CGFloat = 4
    package static let labelBelow: CGFloat = 5
    package static let xAxisExtra: CGFloat = 6
    package static let insideLabelBlock: CGFloat = 20

    /// A record's x coordinate for a value.
    package func x(_ model: _ChartModel, _ value: _PlotValue) -> CGFloat? {
        model.x.fraction(of: value).map { plot.minX + $0 * plot.width }
    }

    package func y(_ model: _ChartModel, _ value: _PlotValue) -> CGFloat? {
        model.y.fraction(of: value).map { plot.maxY - $0 * plot.height }
    }

    /// A bar's extent across a band (or around a continuous x).
    package func bandExtent(_ scale: _Scale, along length: CGFloat, start: CGFloat, value: _PlotValue, dimension: MarkDimension?, inside: Bool, records: [_MarkRecord], axis: Axis) -> (CGFloat, CGFloat)? {
        if let band = scale.band(of: value) {
            let a = start + band.lowerBound * length
            let b = start + band.upperBound * length
            var lo = min(a, b)
            let hi = max(a, b)
            if inside {
                // The label takes the band's top; the bar sits in what is left (measured 2026-10-12).
                lo += Self.insideLabelBlock
            }
            let width = hi - lo
            let size: CGFloat
            switch dimension ?? .automatic {
            case .automatic: size = width * 0.7
            case .fixed(let w): size = min(w, width)
            case .ratio(let r): size = width * r
            case .inset(let i): size = max(width - 2 * i, 0)
            }
            let center = (lo + hi) / 2
            return (center - size / 2, center + size / 2)
        }
        guard let c = scale.fraction(of: value).map({ start + $0 * length }) else { return nil }
        // A continuous axis: the unit's span, else 70 % of the smallest gap between values.
        if let unit = scale.unit, let date = value.date, scale.kind == .temporal {
            let calendar = Calendar.current
            if let unitStart = _unitStart(calendar, unit, date), let unitEnd = calendar.date(byAdding: unit, value: 1, to: unitStart) {
                let a = scale.fraction(of: .date(unitStart)).map { start + $0 * length } ?? c
                let b = scale.fraction(of: .date(unitEnd)).map { start + $0 * length } ?? c
                let inset = (b - a) * 0.15
                return (a + inset, b - inset)
            }
        }
        let positions = Set(records.compactMap { r -> CGFloat? in
            let v = axis == .horizontal ? r.x : r.y
            return v.flatMap { scale.fraction(of: $0) }.map { start + $0 * length }
        }).sorted()
        var gap = length
        for (a, b) in zip(positions, positions.dropFirst()) { gap = min(gap, b - a) }
        if positions.count < 2 { gap = length / 2 }
        let size: CGFloat
        switch dimension ?? .automatic {
        case .automatic: size = gap * 0.7
        case .fixed(let w): size = w
        case .ratio(let r): size = gap * r
        case .inset(let i): size = max(gap - 2 * i, 0)
        }
        return (c - size / 2, c + size / 2)
    }
}

/// The start of the calendar unit holding a date (WebFoundation has no `dateInterval(of:for:)`).
package func _unitStart(_ calendar: Calendar, _ unit: Calendar.Component, _ date: Date) -> Date? {
    let wanted: Set<Calendar.Component>
    switch unit {
    case .year: wanted = [.year]
    case .month: wanted = [.year, .month]
    case .hour: wanted = [.year, .month, .day, .hour]
    case .minute: wanted = [.year, .month, .day, .hour, .minute]
    default: wanted = [.year, .month, .day]
    }
    return calendar.date(from: calendar.dateComponents(wanted, from: date))
}
