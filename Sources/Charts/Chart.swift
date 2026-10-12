// The `Chart` view: collects its content's marks, resolves the scales and paints the grid,
// the marks and the axis labels into a `Canvas` (annotations are the canvas's symbols placed
// against their marks); the legend is a row of swatches below. `chartOverlay` and
// `chartBackground` get a `ChartProxy` over the same geometry.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// A SwiftUI view that displays a chart.
public struct Chart<Content: ChartContent>: View {
    let content: Content

    /// Creates a chart composed of marks.
    public init(@ChartContentBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        var records: [_MarkRecord] = []
        content._collect(into: &records)
        return _ChartBody(records: records)
    }
}

extension Chart {
    /// Creates a chart with a mark for every element of a collection.
    public init<Data: RandomAccessCollection, C: ChartContent>(_ data: Data, @ChartContentBuilder content: @escaping (Data.Element) -> C)
        where Content == ForEach<Data, Data.Element.ID, C>, Data.Element: Identifiable {
        self.content = ForEach(data, content: content)
    }

    public init<Data: RandomAccessCollection, ID: Hashable, C: ChartContent>(_ data: Data, id: KeyPath<Data.Element, ID>, @ChartContentBuilder content: @escaping (Data.Element) -> C)
        where Content == ForEach<Data, ID, C> {
        self.content = ForEach(data, id: id, content: content)
    }
}

/// The geometry a `chartOverlay` / `chartBackground` closure sees.
public struct ChartProxy {
    package let model: _ChartModel
    package let geometry: _ChartGeometry

    /// The plot area's size.
    public var plotSize: CGSize { geometry.plot.size }
    public var plotAreaSize: CGSize { geometry.plot.size }
    /// The plot area's frame in the chart's coordinates (SwiftUIWeb gives the rectangle
    /// itself; Swift Charts an `Anchor<CGRect>`).
    public var plotFrame: CGRect? { geometry.plot }
    public var plotAreaFrame: CGRect? { geometry.plot }

    /// The x position (in the plot's coordinates) for a value.
    public func position<X: Plottable>(forX value: X) -> CGFloat? {
        geometry.x(model, value.primitivePlottable._plotValue).map { $0 - geometry.plot.minX }
    }

    public func position<Y: Plottable>(forY value: Y) -> CGFloat? {
        geometry.y(model, value.primitivePlottable._plotValue).map { $0 - geometry.plot.minY }
    }

    public func position<X: Plottable, Y: Plottable>(for value: (x: X, y: Y)) -> CGPoint? {
        guard let x = position(forX: value.x), let y = position(forY: value.y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// The value at an x position in the plot's coordinates.
    public func value<X: Plottable>(atX position: CGFloat, as type: X.Type = X.self) -> X? {
        guard geometry.plot.width > 0, let v = model.x.value(at: position / geometry.plot.width) else { return nil }
        return _plottable(type, from: v)
    }

    public func value<Y: Plottable>(atY position: CGFloat, as type: Y.Type = Y.self) -> Y? {
        guard geometry.plot.height > 0, let v = model.y.value(at: 1 - position / geometry.plot.height) else { return nil }
        return _plottable(type, from: v)
    }

    public func value<X: Plottable, Y: Plottable>(at point: CGPoint, as type: (X, Y).Type = (X, Y).self) -> (x: X, y: Y)? {
        guard let x: X = value(atX: point.x), let y: Y = value(atY: point.y) else { return nil }
        return (x, y)
    }

    public func angle<A: Plottable>(forValue value: A) -> Angle? { nil }
    public func selectedValue<X: Plottable>(atX position: CGFloat, as type: X.Type = X.self) -> X? { value(atX: position) }
}

/// The chart's body: the plot canvas and the legend.
struct _ChartBody: View {
    let records: [_MarkRecord]
    @Environment(\._chartConfiguration) private var configuration
    @Environment(\.platformProfile) private var platform

    private var labelFont: Font { Font.system(size: platform.name == "iOS" ? 12 : 11) }
    private var model: _ChartModel { _ChartModel(records: records, configuration: configuration) }

    private var legendVisible: Bool {
        switch configuration.legend.visibility {
        case .hidden: return false
        case .visible: return true
        case .automatic: return !model.series.isEmpty
        }
    }

    var body: some View {
        let model = self.model
        let annotations = symbolEntries(model)
        let canvas = Canvas { context, size in
            var painter = _ChartPainter(model: model, configuration: configuration, labelFont: labelFont, context: context, size: size)
            painter.paint()
        } symbols: {
            ForEach(annotations) { entry in entry.view.tag(entry.id) }
        }._unclipped()
        let plot = configuration.plotStyle.map { $0(ChartPlotContent(content: AnyView(canvas))) } ?? AnyView(canvas)
        let needsProxy = configuration.overlay != nil || configuration.background != nil
        let legendPosition = configuration.legend.position
        let legendSpacing = configuration.legend.spacing ?? 8
        VStack(alignment: .leading, spacing: legendSpacing) {
            if legendVisible && legendPosition == .top { legend(model) }
            HStack(alignment: .center, spacing: legendSpacing) {
                if legendVisible && legendPosition == .leading { legend(model) }
                if needsProxy {
                    GeometryReader { geometry in
                        let proxy = proxy(model, size: geometry.size)
                        ZStack {
                            if let background = configuration.background { background(proxy) }
                            plot
                            if let overlay = configuration.overlay { overlay(proxy) }
                        }
                    }
                } else {
                    plot
                }
                if legendVisible && legendPosition == .trailing { legend(model) }
            }
            if legendVisible && (legendPosition == .bottom || legendPosition == .automatic || legendPosition == .overlay) { legend(model) }
        }
    }

    /// The proxy for a plot size: the geometry with estimated label widths and the scales
    /// finished for it.
    private func proxy(_ model: _ChartModel, size: CGSize) -> ChartProxy {
        var finished = model
        let geometry = _ChartPainter.geometry(finishing: &finished, configuration: configuration, size: size, labelHeight: _axisLabelLineHeight(platform), labelWidth: { estimatedWidth($0) })
        return ChartProxy(model: finished, geometry: geometry)
    }

    /// The canvas's symbols: the annotations and the axis titles.
    private func symbolEntries(_ model: _ChartModel) -> [_SymbolEntry] {
        var entries = model.records.flatMap { r in r.annotations.enumerated().map { _SymbolEntry(id: "\(r.index).\($0.offset)", view: $0.element.content) } }
        if let title = configuration.xAxisLabel { entries.append(_SymbolEntry(id: "axis.x", view: title)) }
        if let title = configuration.yAxisLabel { entries.append(_SymbolEntry(id: "axis.y", view: title)) }
        return entries
    }

    /// A label's width without the engine: an average glyph of 0.56 em.
    private func estimatedWidth(_ text: String) -> CGFloat {
        CGFloat(text.count) * (platform.name == "iOS" ? 12 : 11) * 0.56
    }

    @ViewBuilder
    private func legend(_ model: _ChartModel) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(model.series.enumerated()), id: \.offset) { entry in
                HStack(spacing: 5) {
                    _LegendSwatch(style: entry.element.style, symbol: model.symbolsBySeries[entry.element.name] ?? .circle)
                    Text(entry.element.name).font(labelFont).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct _SymbolEntry: Identifiable {
    let id: String
    let view: AnyView
}

/// A legend's 8 pt swatch.
struct _LegendSwatch: View {
    let style: AnyShapeStyle
    let symbol: _SymbolShape
    var body: some View {
        _SymbolPath(symbol: symbol).fill(style).frame(width: 8, height: 8)
    }
}

/// The symbol shapes as a `Shape`.
struct _SymbolPath: Shape {
    let symbol: _SymbolShape
    func path(in rect: CGRect) -> Path { _symbolPath(symbol, in: rect) }
}

func _symbolPath(_ symbol: _SymbolShape, in rect: CGRect) -> Path {
    var path = Path()
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let r = min(rect.width, rect.height) / 2
    switch symbol {
    case .circle: path.addEllipse(in: rect)
    case .square: path.addRect(rect)
    case .triangle:
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
        path.closeSubpath()
    case .diamond:
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addLine(to: CGPoint(x: c.x + r, y: c.y))
        path.addLine(to: CGPoint(x: c.x, y: c.y + r))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y))
        path.closeSubpath()
    case .cross:
        let t = r * 0.35
        for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
            var bar = Path()
            bar.addRect(CGRect(x: -r, y: -t / 2, width: 2 * r, height: t))
            path.addPath(bar.applying(CGAffineTransform(rotationAngle: angle)).applying(CGAffineTransform(translationX: c.x, y: c.y)))
        }
    case .plus:
        let t = r * 0.35
        path.addRect(CGRect(x: c.x - r, y: c.y - t / 2, width: 2 * r, height: t))
        path.addRect(CGRect(x: c.x - t / 2, y: c.y - r, width: t, height: 2 * r))
    case .asterisk:
        let t = r * 0.3
        for i in 0..<3 {
            let angle = CGFloat(i) * .pi / 3
            var bar = Path()
            bar.addRect(CGRect(x: -r, y: -t / 2, width: 2 * r, height: t))
            path.addPath(bar.applying(CGAffineTransform(rotationAngle: angle)).applying(CGAffineTransform(translationX: c.x, y: c.y)))
        }
    case .pentagon:
        for i in 0..<5 {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 5
            let p = CGPoint(x: c.x + r * CGFloat(_cos(Double(angle))), y: c.y + r * CGFloat(_sin(Double(angle))))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
    }
    return path
}

/// The line height of an axis label without the engine (the proxy's geometry; the painter
/// measures the real one).
func _axisLabelLineHeight(_ platform: PlatformProfile) -> CGFloat {
    platform.name == "iOS" ? 15 : 14
}

// MARK: - Painting

/// Paints one chart into a canvas context.
@MainActor
struct _ChartPainter {
    var model: _ChartModel
    let configuration: _ChartConfiguration
    let labelFont: Font
    let context: GraphicsContext
    let size: CGSize

    static let gridColor = Color.primary.opacity(0.13)

    func label(_ text: String) -> Text { Text(text).font(labelFont).foregroundStyle(Color.secondary) }

    /// The geometry for a size, given a way to measure labels.
    package static func geometry(model: _ChartModel, configuration: _ChartConfiguration, size: CGSize, labelHeight: CGFloat, labelWidth: (String) -> CGFloat) -> _ChartGeometry {
        var model = model
        return geometry(finishing: &model, configuration: configuration, size: size, labelHeight: labelHeight, labelWidth: labelWidth)
    }

    /// The geometry, leaving the model's scales finished for the plot's lengths.
    package static func geometry(finishing model: inout _ChartModel, configuration: _ChartConfiguration, size: CGSize, labelHeight: CGFloat, labelWidth: (String) -> CGFloat) -> _ChartGeometry {
        let xVisible = configuration.xAxis.visibility != .hidden
        let yVisible = configuration.yAxis.visibility != .hidden
        let yPosition = configuration.yAxis.marks?.first?.position ?? .automatic
        let yLeading = yPosition == .leading
        let yInside = model.y.isNominal && yLeading
        var plot = CGRect(origin: .zero, size: size)
        // The x labels take a block below the plot.
        let xHasLabels = xVisible && (configuration.xAxis.marks?.first.map { $0.parts.contains { $0.kind == .label } || $0.partsForValue != nil } ?? true)
        if xHasLabels { plot.size.height -= labelHeight + _ChartGeometry.xAxisExtra }
        if configuration.xAxisLabel != nil { plot.size.height -= labelHeight + 4 }
        // The y labels a column beside it (unless drawn inside the bands).
        _ChartModel.finish(&model.y, length: plot.height, marks: configuration.yAxis.marks, fixedDomain: configuration.yDomain != nil)
        let yHasLabels = yVisible && (configuration.yAxis.marks?.first.map { $0.parts.contains { $0.kind == .label } || $0.partsForValue != nil } ?? true)
        if yHasLabels && !yInside {
            let widest = model.y.ticks.map { labelWidth($0.label) }.max() ?? 0
            let column = widest.rounded(.up) + _ChartGeometry.labelGap
            if yLeading { plot.origin.x += column }
            plot.size.width -= column
        }
        if configuration.yAxisLabel != nil {
            plot.origin.y += labelHeight + 4
            plot.size.height -= labelHeight + 4
        }
        _ChartModel.finish(&model.x, length: plot.width, marks: configuration.xAxis.marks, fixedDomain: configuration.xDomain != nil)
        return _ChartGeometry(plot: plot, labelHeight: labelHeight, xLabelsVisible: xHasLabels, yLabelsVisible: yHasLabels, yAxisLeading: yLeading, yLabelsInside: yInside)
    }

    mutating func paint() {
        let sample = context.resolve(label("0"))
        let labelHeight = sample.measure(in: CGSize(width: 1000, height: 1000)).height
        var finished = model
        let geometry = Self.geometry(finishing: &finished, configuration: configuration, size: size, labelHeight: labelHeight) { text in
            context.resolve(label(text)).measure(in: CGSize(width: 1000, height: 1000)).width
        }
        model = finished
        let plot = geometry.plot
        guard plot.width > 0, plot.height > 0 else { return }

        paintGrid(geometry)
        var frames: [Int: CGRect] = [:]
        let ordered = model.records.indices.sorted { (model.records[$0].zIndex, $0) < (model.records[$1].zIndex, $1) }
        // Lines and areas join the records of a series; the others paint one by one.
        var painted = Set<Int>()
        for i in ordered where !painted.contains(i) {
            let r = model.records[i]
            switch r.kind {
            case .line, .area:
                let members = ordered.filter { j in
                    let o = model.records[j]
                    return j == i || (!painted.contains(j) && o.kind == r.kind && o.series == r.series && o.dodge == r.dodge)
                }
                let frame = paintPath(members, kind: r.kind, geometry: geometry)
                for m in members { painted.insert(m); frames[m] = frame }
            case .bar, .rectangle:
                frames[i] = paintBar(r, geometry: geometry); painted.insert(i)
            case .point:
                frames[i] = paintPoint(r, geometry: geometry); painted.insert(i)
            case .rule:
                frames[i] = paintRule(r, geometry: geometry); painted.insert(i)
            }
        }
        paintLabels(geometry)
        for (i, r) in model.records.enumerated() where !r.annotations.isEmpty {
            guard let frame = frames[i] else { continue }
            for (j, annotation) in r.annotations.enumerated() {
                paintAnnotation(annotation, id: "\(r.index).\(j)", frame: frame, geometry: geometry)
            }
        }
    }

    // MARK: Grid and labels

    private func gridStroke(dashed: Bool, custom: StrokeStyle?) -> StrokeStyle {
        if let custom { return custom }
        return StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : [])
    }

    private func xParts(for tick: _Tick, index: Int, count: Int) -> [_AxisPart] {
        guard let marks = configuration.xAxis.marks?.first else { return _AxisPart.defaults }
        return marks.resolvedParts(for: AxisValue(index: index, count: count, value: tick.value))
    }

    private func yParts(for tick: _Tick, index: Int, count: Int) -> [_AxisPart] {
        guard let marks = configuration.yAxis.marks?.first else { return _AxisPart.defaults }
        return marks.resolvedParts(for: AxisValue(index: index, count: count, value: tick.value))
    }

    private mutating func paintGrid(_ geometry: _ChartGeometry) {
        let plot = geometry.plot
        if configuration.xAxis.visibility != .hidden {
            // A nominal axis rules the band edges; a continuous one its ticks.
            let positions: [(CGFloat, _AxisPart?)]
            if model.x.isNominal {
                let n = model.x.ticks.count
                positions = (0...max(n, 1)).map { i in (plot.minX + CGFloat(i) / CGFloat(max(n, 1)) * plot.width, gridPart(xParts(for: model.x.ticks[min(i, max(n - 1, 0))], index: min(i, max(n - 1, 0)), count: n))) }
            } else {
                positions = model.x.ticks.enumerated().map { ($0.element.fraction * plot.width + plot.minX, gridPart(xParts(for: $0.element, index: $0.offset, count: model.x.ticks.count))) }
            }
            for (x, part) in positions {
                guard let part else { continue }
                var line = Path()
                line.move(to: CGPoint(x: x, y: plot.minY))
                line.addLine(to: CGPoint(x: x, y: plot.maxY))
                context.stroke(line, with: .color(part.color ?? Self.gridColor), style: gridStroke(dashed: true, custom: part.stroke ?? configuration.xAxis.marks?.first?.stroke))
            }
        }
        if configuration.yAxis.visibility != .hidden {
            let positions: [(CGFloat, _AxisPart?)]
            if model.y.isNominal {
                let n = model.y.ticks.count
                positions = (0...max(n, 1)).map { i in (plot.maxY - CGFloat(i) / CGFloat(max(n, 1)) * plot.height, gridPart(yParts(for: model.y.ticks[min(i, max(n - 1, 0))], index: min(i, max(n - 1, 0)), count: n))) }
            } else {
                positions = model.y.ticks.enumerated().map { (plot.maxY - $0.element.fraction * plot.height, gridPart(yParts(for: $0.element, index: $0.offset, count: model.y.ticks.count))) }
            }
            for (y, part) in positions {
                guard let part else { continue }
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y))
                line.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(line, with: .color(part.color ?? Self.gridColor), style: gridStroke(dashed: false, custom: part.stroke ?? configuration.yAxis.marks?.first?.stroke))
            }
        }
    }

    private func gridPart(_ parts: [_AxisPart]) -> _AxisPart? { parts.first { $0.kind == .gridLine } }
    private func labelPart(_ parts: [_AxisPart]) -> _AxisPart? { parts.first { $0.kind == .label } }

    private func labelText(for tick: _Tick, part: _AxisPart) -> String {
        part.format?(tick.value) ?? tick.label
    }

    private mutating func paintLabels(_ geometry: _ChartGeometry) {
        let plot = geometry.plot
        if geometry.xLabelsVisible {
            let count = model.x.ticks.count
            for (i, tick) in model.x.ticks.enumerated() {
                guard let part = labelPart(xParts(for: tick, index: i, count: count)) else { continue }
                let text = context.resolve(label(labelText(for: tick, part: part)))
                let width = text.measure(in: CGSize(width: 1000, height: 1000)).width
                let y = plot.maxY + _ChartGeometry.labelBelow
                if model.x.isNominal {
                    let center = plot.minX + tick.fraction * plot.width
                    context.draw(text, at: CGPoint(x: center, y: y), anchor: .top)
                } else {
                    // Leading of the tick, 4 pt after it; a label past the plot's end is dropped.
                    let x = plot.minX + tick.fraction * plot.width + _ChartGeometry.labelGap
                    guard x + width <= plot.maxX + 0.5 else { continue }
                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .topLeading)
                }
            }
            if configuration.xAxisLabel != nil, let symbol = context.resolveSymbol(id: "axis.x") {
                context.draw(symbol, at: CGPoint(x: plot.midX, y: plot.maxY + _ChartGeometry.labelBelow + geometry.labelHeight + 4), anchor: .top)
            }
        }
        if configuration.yAxisLabel != nil, let symbol = context.resolveSymbol(id: "axis.y") {
            let x = geometry.yAxisLeading ? plot.minX - _ChartGeometry.labelGap : plot.maxX + _ChartGeometry.labelGap
            context.draw(symbol, at: CGPoint(x: x, y: plot.minY - 4), anchor: geometry.yAxisLeading ? .bottomTrailing : .bottomLeading)
        }
        if geometry.yLabelsVisible {
            let count = model.y.ticks.count
            for (i, tick) in model.y.ticks.enumerated() {
                guard let part = labelPart(yParts(for: tick, index: i, count: count)) else { continue }
                let text = context.resolve(label(labelText(for: tick, part: part)))
                if geometry.yLabelsInside {
                    // Inside the band's top, leading (horizontal bar charts).
                    let top = plot.maxY - tick.bandEnd * plot.height
                    context.draw(text, at: CGPoint(x: plot.minX + _ChartGeometry.labelGap, y: top + _ChartGeometry.labelBelow), anchor: .topLeading)
                } else if model.y.isNominal {
                    let center = plot.maxY - tick.fraction * plot.height
                    if geometry.yAxisLeading {
                        context.draw(text, at: CGPoint(x: plot.minX - _ChartGeometry.labelGap, y: center), anchor: .trailing)
                    } else {
                        context.draw(text, at: CGPoint(x: plot.maxX + _ChartGeometry.labelGap, y: center), anchor: .leading)
                    }
                } else {
                    let y = plot.maxY - tick.fraction * plot.height
                    if geometry.yAxisLeading {
                        context.draw(text, at: CGPoint(x: plot.minX - _ChartGeometry.labelGap, y: y), anchor: .trailing)
                    } else {
                        context.draw(text, at: CGPoint(x: plot.maxX + _ChartGeometry.labelGap, y: y), anchor: .leading)
                    }
                }
            }
        }
    }

    // MARK: Marks

    private func shading(_ r: _MarkRecord) -> GraphicsContext.Shading {
        if let style = r.style { return .style(style) }
        return .color(_ChartModel.defaultColor)
    }

    private func withOpacity(_ r: _MarkRecord, _ body: (GraphicsContext) -> Void) {
        if r.opacity < 1 {
            var faded = context
            faded.opacity *= r.opacity
            body(faded)
        } else {
            body(context)
        }
    }

    /// A bar or rectangle: a band on one axis, a value or range on the other.
    private func paintBar(_ r: _MarkRecord, geometry: _ChartGeometry) -> CGRect? {
        let plot = geometry.plot
        var rect: CGRect
        let xValue = r.x ?? r.xStart
        let yValue = r.y ?? r.yStart
        // Which axis holds the band: the nominal one, else the one with a single value.
        let horizontalBand: Bool
        if model.x.isNominal, xValue != nil { horizontalBand = true }
        else if model.y.isNominal, yValue != nil { horizontalBand = false }
        else if r.xStart != nil, r.xEnd != nil, r.yStart != nil, r.yEnd != nil {
            // A rectangle between four values.
            guard let x0 = geometry.x(model, r.xStart!), let x1 = geometry.x(model, r.xEnd!), let y0 = geometry.y(model, r.yStart!), let y1 = geometry.y(model, r.yEnd!) else { return nil }
            let rect = CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0)).offsetBy(dx: r.offset.width, dy: r.offset.height)
            withOpacity(r) { ctx in ctx.fill(r.cornerRadius > 0 ? Path(roundedRect: rect, cornerRadius: r.cornerRadius) : Path(rect), with: shading(r)) }
            return rect
        }
        else if r.xStart != nil, r.xEnd != nil { horizontalBand = false }
        else { horizontalBand = true }
        if horizontalBand, let xv = xValue {
            guard let (x0, x1) = geometry.bandExtent(model.x, along: plot.width, start: plot.minX, value: xv, dimension: r.width, inside: false, records: model.records, axis: .horizontal) else { return nil }
            let yStart = r.yStart.flatMap { geometry.y(model, $0) } ?? geometry.y(model, .number(0)) ?? plot.maxY
            let yEnd = (r.yEnd ?? r.y).flatMap { geometry.y(model, $0) } ?? plot.minY
            rect = CGRect(x: x0, y: min(yStart, yEnd), width: x1 - x0, height: abs(yEnd - yStart))
            // The band may be dodged into sub-bands.
            if let dodge = r.dodge, !model.y.isNominal {
                let dodges = dodgeValues(for: r)
                if let index = dodges.firstIndex(of: dodge), dodges.count > 1 {
                    let w = rect.width / CGFloat(dodges.count)
                    rect = CGRect(x: rect.minX + CGFloat(index) * w, y: rect.minY, width: w, height: rect.height)
                }
            }
            rect = rect.offsetBy(dx: r.offset.width, dy: r.offset.height)
            withOpacity(r) { ctx in ctx.fill(barPath(rect, radius: r.cornerRadius, towards: yEnd <= yStart ? .top : .bottom), with: shading(r)) }
        } else if let yv = yValue {
            guard let (y1, y0) = geometry.bandExtent(model.y, along: -plot.height, start: plot.maxY, value: yv, dimension: r.height, inside: geometry.yLabelsInside, records: model.records, axis: .vertical).map({ ($0.0, $0.1) }) else { return nil }
            let xStart = r.xStart.flatMap { geometry.x(model, $0) } ?? geometry.x(model, .number(0)) ?? plot.minX
            let xEnd = (r.xEnd ?? r.x).flatMap { geometry.x(model, $0) } ?? plot.maxX
            rect = CGRect(x: min(xStart, xEnd), y: min(y0, y1), width: abs(xEnd - xStart), height: abs(y1 - y0))
            if let dodge = r.dodge {
                let dodges = dodgeValues(for: r)
                if let index = dodges.firstIndex(of: dodge), dodges.count > 1 {
                    let h = rect.height / CGFloat(dodges.count)
                    rect = CGRect(x: rect.minX, y: rect.minY + CGFloat(index) * h, width: rect.width, height: h)
                }
            }
            rect = rect.offsetBy(dx: r.offset.width, dy: r.offset.height)
            withOpacity(r) { ctx in ctx.fill(barPath(rect, radius: r.cornerRadius, towards: xEnd >= xStart ? .trailing : .leading), with: shading(r)) }
        } else {
            return nil
        }
        return rect
    }

    private func dodgeValues(for r: _MarkRecord) -> [String] {
        var values: [String] = []
        for other in model.records where other.kind == r.kind {
            if let d = other.dodge, !values.contains(d) { values.append(d) }
        }
        return values
    }

    /// Bars round the corners at their value end only (measured: a 4 pt radius leaves the
    /// baseline end square).
    private func barPath(_ rect: CGRect, radius: CGFloat, towards edge: Edge) -> Path {
        guard radius > 0 else { return Path(rect) }
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        switch edge {
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }

    private func symbolDiameter(_ r: _MarkRecord) -> CGFloat {
        let area = r.symbolSize ?? _defaultSymbolArea
        return 2 * CGFloat((Double(area) / Double.pi).squareRoot())
    }

    private func paintPoint(_ r: _MarkRecord, geometry: _ChartGeometry) -> CGRect? {
        guard let xv = r.x, let yv = r.y, let x = geometry.x(model, xv), let y = geometry.y(model, yv) else { return nil }
        let d = symbolDiameter(r)
        let rect = CGRect(x: x - d / 2 + r.offset.width, y: y - d / 2 + r.offset.height, width: d, height: d)
        withOpacity(r) { ctx in ctx.fill(_symbolPath(r.symbol, in: rect), with: shading(r)) }
        return rect
    }

    /// A rule: across the plot at a value, or between two values; 2 pt with round caps.
    private func paintRule(_ r: _MarkRecord, geometry: _ChartGeometry) -> CGRect? {
        let plot = geometry.plot
        let style = r.lineStyle ?? StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        var path = Path()
        var frame: CGRect
        if let yv = r.y ?? r.yStart, r.x == nil, r.xStart == nil || r.xEnd == nil {
            guard let y = geometry.y(model, yv) else { return nil }
            let x0 = r.xStart.flatMap { geometry.x(model, $0) } ?? plot.minX
            let x1 = r.xEnd.flatMap { geometry.x(model, $0) } ?? plot.maxX
            path.move(to: CGPoint(x: x0, y: y)); path.addLine(to: CGPoint(x: x1, y: y))
            frame = CGRect(x: x0, y: y - style.lineWidth / 2, width: x1 - x0, height: style.lineWidth)
        } else if let xv = r.x ?? r.xStart, r.y == nil, r.yStart == nil || r.yEnd == nil {
            guard let x = geometry.x(model, xv) else { return nil }
            let y0 = r.yStart.flatMap { geometry.y(model, $0) } ?? plot.maxY
            let y1 = r.yEnd.flatMap { geometry.y(model, $0) } ?? plot.minY
            path.move(to: CGPoint(x: x, y: y0)); path.addLine(to: CGPoint(x: x, y: y1))
            frame = CGRect(x: x - style.lineWidth / 2, y: min(y0, y1), width: style.lineWidth, height: abs(y1 - y0))
        } else if let xv = r.x, let y0v = r.yStart, let y1v = r.yEnd {
            guard let x = geometry.x(model, xv), let y0 = geometry.y(model, y0v), let y1 = geometry.y(model, y1v) else { return nil }
            path.move(to: CGPoint(x: x, y: y0)); path.addLine(to: CGPoint(x: x, y: y1))
            frame = CGRect(x: x - style.lineWidth / 2, y: min(y0, y1), width: style.lineWidth, height: abs(y1 - y0))
        } else if let yv = r.y, let x0v = r.xStart, let x1v = r.xEnd {
            guard let y = geometry.y(model, yv), let x0 = geometry.x(model, x0v), let x1 = geometry.x(model, x1v) else { return nil }
            path.move(to: CGPoint(x: x0, y: y)); path.addLine(to: CGPoint(x: x1, y: y))
            frame = CGRect(x: min(x0, x1), y: y - style.lineWidth / 2, width: abs(x1 - x0), height: style.lineWidth)
        } else if let x0v = r.xStart, let x1v = r.xEnd, let y0v = r.yStart, let y1v = r.yEnd {
            guard let x0 = geometry.x(model, x0v), let x1 = geometry.x(model, x1v), let y0 = geometry.y(model, y0v), let y1 = geometry.y(model, y1v) else { return nil }
            path.move(to: CGPoint(x: x0, y: y0)); path.addLine(to: CGPoint(x: x1, y: y1))
            frame = CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
        } else {
            return nil
        }
        path = path.applying(CGAffineTransform(translationX: r.offset.width, y: r.offset.height))
        withOpacity(r) { ctx in ctx.stroke(path, with: shading(r), style: style) }
        return frame.offsetBy(dx: r.offset.width, dy: r.offset.height)
    }

    /// A line or area through a series' records, in data order.
    private func paintPath(_ members: [Int], kind: _MarkKind, geometry: _ChartGeometry) -> CGRect? {
        let plot = geometry.plot
        let records = members.map { model.records[$0] }
        guard let first = records.first else { return nil }
        var points: [CGPoint] = []
        var lows: [CGPoint] = []
        for r in records {
            guard let xv = r.x, let x = geometry.x(model, xv) else { continue }
            let top = (r.yEnd ?? r.y).flatMap { geometry.y(model, $0) }
            guard let y = top else { continue }
            points.append(CGPoint(x: x + r.offset.width, y: y + r.offset.height))
            let low = r.yStart.flatMap { geometry.y(model, $0) } ?? (model.y.isNominal ? plot.maxY : (geometry.y(model, .number(0)) ?? plot.maxY))
            lows.append(CGPoint(x: x + r.offset.width, y: min(max(low, plot.minY), plot.maxY) + r.offset.height))
        }
        guard !points.isEmpty else { return nil }
        let upper = _interpolated(points, method: first.interpolation)
        var frame = upper.boundingRect
        if kind == .line {
            let style = first.lineStyle ?? StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            withOpacity(first) { ctx in ctx.stroke(upper, with: shading(first), style: style) }
            if first.symbolSize != nil {
                let d = symbolDiameter(first)
                for p in points {
                    withOpacity(first) { ctx in ctx.fill(_symbolPath(first.symbol, in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: shading(first)) }
                }
            }
            frame = frame.insetBy(dx: -style.lineWidth / 2, dy: -style.lineWidth / 2)
        } else {
            var area = upper
            for p in lows.reversed() { area.addLine(to: p) }
            area.closeSubpath()
            withOpacity(first) { ctx in ctx.fill(area, with: shading(first)) }
            frame = area.boundingRect
        }
        return frame
    }

    // MARK: Annotations

    private func paintAnnotation(_ annotation: _Annotation, id: String, frame: CGRect, geometry: _ChartGeometry) {
        guard let symbol = context.resolveSymbol(id: id) else { return }
        let size = symbol.size
        let spacing = annotation.spacing ?? 4
        var position = annotation.position
        if position == .automatic { position = .top }
        let alignment = annotation.alignment
        func alignedX() -> CGFloat {
            switch alignment.horizontal {
            case .leading: return frame.minX
            case .trailing: return frame.maxX - size.width
            default: return frame.midX - size.width / 2
            }
        }
        func alignedY() -> CGFloat {
            switch alignment.vertical {
            case .top: return frame.minY
            case .bottom: return frame.maxY - size.height
            default: return frame.midY - size.height / 2
            }
        }
        var origin: CGPoint
        switch position {
        case .top: origin = CGPoint(x: alignedX(), y: frame.minY - spacing - size.height)
        case .bottom: origin = CGPoint(x: alignedX(), y: frame.maxY + spacing)
        case .leading: origin = CGPoint(x: frame.minX - spacing - size.width, y: alignedY())
        case .trailing: origin = CGPoint(x: frame.maxX + spacing, y: alignedY())
        case .topLeading: origin = CGPoint(x: frame.minX - spacing - size.width, y: frame.minY - spacing - size.height)
        case .topTrailing: origin = CGPoint(x: frame.maxX + spacing, y: frame.minY - spacing - size.height)
        case .bottomLeading: origin = CGPoint(x: frame.minX - spacing - size.width, y: frame.maxY + spacing)
        case .bottomTrailing: origin = CGPoint(x: frame.maxX + spacing, y: frame.maxY + spacing)
        case .overlay, .automatic: origin = CGPoint(x: alignedX(), y: alignedY())
        }
        context.draw(symbol, in: CGRect(origin: origin, size: size))
    }
}

/// A path through points by an interpolation method.
func _interpolated(_ points: [CGPoint], method: InterpolationMethod) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 1 else { return path }
    switch method {
    case .linear:
        for p in points.dropFirst() { path.addLine(to: p) }
    case .stepStart:
        for (a, b) in zip(points, points.dropFirst()) { path.addLine(to: CGPoint(x: a.x, y: b.y)); path.addLine(to: b) }
    case .stepEnd:
        for (a, b) in zip(points, points.dropFirst()) { path.addLine(to: CGPoint(x: b.x, y: a.y)); path.addLine(to: b) }
    case .stepCenter:
        for (a, b) in zip(points, points.dropFirst()) {
            let mid = (a.x + b.x) / 2
            path.addLine(to: CGPoint(x: mid, y: a.y)); path.addLine(to: CGPoint(x: mid, y: b.y)); path.addLine(to: b)
        }
    case .catmullRom, .cardinal, .monotone:
        // Catmull-Rom as cubic Béziers (tension 0.5; monotone clamps overshoot by halving the tangents).
        let tension: CGFloat = method == .monotone ? 0.25 : 0.5
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension / 3, y: p1.y + (p2.y - p0.y) * tension / 3)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension / 3, y: p2.y - (p3.y - p1.y) * tension / 3)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
    return path
}
