// Swift Charts (sw-frameworks, Docs/elements/Charts.md): marks collect into records, the scales
// make nice domains and bands, stacking and dodging follow the series, and the painted chart
// puts bars, grid lines and labels where Apple's Charts does (measured on macOS 27).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Charts

#if !os(WASI)
@Suite @MainActor struct ChartsTests {
    struct Sale: Identifiable {
        let id = UUID()
        let month: String
        let amount: Double
        let kind: String
    }

    static let sales = [Sale(month: "Jan", amount: 42, kind: "Online"), Sale(month: "Feb", amount: 58, kind: "Online"), Sale(month: "Mar", amount: 90, kind: "Online")]
    static let stores = [Sale(month: "Jan", amount: 30, kind: "Store"), Sale(month: "Feb", amount: 25, kind: "Store"), Sale(month: "Mar", amount: 45, kind: "Store")]

    private func records<C: ChartContent>(@ChartContentBuilder _ content: () -> C) -> [_MarkRecord] {
        var out: [_MarkRecord] = []
        content()._collect(into: &out)
        return out
    }

    private func drawn(_ commands: [DisplayCommand]) -> [String] {
        commands.compactMap { command -> String? in
            if case .drawText(let string, _, _, _) = command { return string }
            return nil
        }
    }

    /// A chart's display list at a size, with 11 pt labels 13 tall (the macOS metrics).
    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 240)) -> (Runtime, [DisplayCommand]) {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: size)
        return (runtime, runtime.render(scale: 2).commands)
    }

    @Test func marksCollectIntoRecords() {
        let out = records {
            BarMark(x: .value("Month", "Jan"), y: .value("Sales", 42))
                .foregroundStyle(by: .value("Kind", "Online"))
                .cornerRadius(4)
            ForEach(Self.stores) { sale in
                LineMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
                    .interpolationMethod(.catmullRom)
            }
            if Self.stores.count > 2 {
                RuleMark(y: .value("Average", 60)).annotation(position: .top, alignment: .leading) { Text("Average") }
            }
        }
        #expect(out.count == 5)
        #expect(out[0].kind == .bar && out[0].x == .category("Jan") && out[0].y == .number(42) && out[0].series == "Online" && out[0].seriesLabel == "Kind" && out[0].cornerRadius == 4)
        #expect(out[1].kind == .line && out[1].interpolation == .catmullRom && out[3].x == .category("Mar"))
        #expect(out[4].kind == .rule && out[4].y == .number(60) && out[4].annotations.count == 1 && out[4].annotations[0].position == .top)
        #expect(out.map(\.index) == [0, 1, 2, 3, 4])
    }

    @Test func plottableTypes() {
        enum Kind: String, Plottable { case online, store }
        #expect(PlottableValue.value("n", 3).plotValue == .number(3))
        #expect(PlottableValue.value("f", Float(2.5)).plotValue == .number(2.5))
        #expect(PlottableValue.value("s", "x").plotValue == .category("x"))
        #expect(PlottableValue.value("k", Kind.store).plotValue == .category("store"))
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(PlottableValue.value("d", date).plotValue == .date(date))
        #expect(_PlotValue.number(1500).label == "1,500" && _PlotValue.number(2.5).label == "2.5" && _PlotValue.number(0.125).label == "0.13")
    }

    @Test func niceDomainsAndBands() {
        #expect(_ChartModel.niceStep(22.5) == 25 && _ChartModel.niceStep(18) == 20 && _ChartModel.niceStep(0.3) == 0.5 && _ChartModel.niceStep(120) == 200)
        let model = _ChartModel(records: records {
            ForEach(Self.sales) { sale in BarMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount)) }
        }, configuration: _ChartConfiguration())
        var y = model.y
        _ChartModel.finish(&y, length: 188, marks: nil, fixedDomain: false)
        // 0...90 with four intervals: a 25 step up to 100, five ticks.
        #expect(y.domain == 0...100 && y.ticks.map(\.label) == ["0", "25", "50", "75", "100"])
        #expect(model.x.isNominal && model.x.categories == ["Jan", "Feb", "Mar"])
        #expect(model.x.fraction(of: .category("Feb")) == 0.5 && model.x.band(of: .category("Jan")) == 0...(1.0 / 3))
        // A y band runs top to bottom.
        let horizontal = _ChartModel(records: records {
            ForEach(Self.sales) { sale in BarMark(x: .value("Sales", sale.amount), y: .value("Month", sale.month)) }
        }, configuration: _ChartConfiguration())
        #expect(horizontal.y.isNominal && horizontal.y.fraction(of: .category("Jan")).map { abs($0 - 5.0 / 6) < 1e-9 } == true)
        // Lines include zero too; a fixed domain is kept.
        var configuration = _ChartConfiguration()
        configuration.yDomain = .numbers(10...50)
        let fixed = _ChartModel(records: records {
            ForEach(Self.stores) { sale in LineMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount)) }
        }, configuration: configuration)
        var fy = fixed.y
        _ChartModel.finish(&fy, length: 100, marks: nil, fixedDomain: true)
        #expect(fy.domain == 10...50 && fy.ticks.map(\.label) == ["10", "20", "30", "40", "50"])
    }

    @Test func temporalScale() {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 15
        let calendar = Calendar.current
        let jan = calendar.date(from: components)!
        components.month = 4
        let apr = calendar.date(from: components)!
        let model = _ChartModel(records: records {
            LineMark(x: .value("Day", jan), y: .value("v", 1))
            LineMark(x: .value("Day", apr), y: .value("v", 2))
        }, configuration: _ChartConfiguration())
        var x = model.x
        _ChartModel.finish(&x, length: 300, marks: nil, fixedDomain: false)
        #expect(x.kind == .temporal && x.ticks.map(\.label) == ["Feb", "Mar", "Apr"])
        #expect(x.fraction(of: .date(jan)) == 0 && x.fraction(of: .date(apr)) == 1)
    }

    @Test func stackingAndDodging() {
        let stacked = _ChartModel(records: records {
            ForEach(Self.sales + Self.stores) { sale in
                BarMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount)).foregroundStyle(by: .value("Kind", sale.kind))
            }
        }, configuration: _ChartConfiguration())
        #expect(stacked.series.map(\.name) == ["Online", "Store"])
        #expect(stacked.records[0].yStart == .number(0) && stacked.records[0].yEnd == .number(42))
        #expect(stacked.records[3].yStart == .number(42) && stacked.records[3].yEnd == .number(72))
        #expect(stacked.y.domain.upperBound == 135)   // Mar: 90 + 45 before the nice rounding
        let dodged = _ChartModel(records: records {
            ForEach(Self.sales + Self.stores) { sale in
                BarMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
                    .foregroundStyle(by: .value("Kind", sale.kind))
                    .position(by: .value("Kind", sale.kind))
            }
        }, configuration: _ChartConfiguration())
        #expect(dodged.records[3].yStart == nil && dodged.records[3].dodge == "Store" && dodged.y.domain.upperBound == 90)
    }

    @Test func foregroundStyleScaleOrdersTheLegend() {
        let (_, commands) = render(Chart(Self.sales + Self.stores) { sale in
            LineMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount)).foregroundStyle(by: .value("Kind", sale.kind))
        }.chartForegroundStyleScale(["Store": Color.red, "Online": Color.blue]))
        let texts = drawn(commands)
        #expect(texts.firstIndex(of: "Store")! < texts.firstIndex(of: "Online")!)
        // The lines take the mapping's colours.
        let strokes = commands.compactMap { command -> RGBA? in
            if case .strokePath(_, let style, let color) = command, style.lineWidth == 2 { return color }
            return nil
        }
        #expect(strokes.count == 2 && strokes[0].blue == 1 && strokes[1].red == 1)
    }

    @Test func barChartGeometryMatchesTheMeasurements() {
        // charts/bar: 288 × 208 inside 16 pt padding; the y column takes 24 (a 20 pt "100" + 4),
        // the x labels 20 below; bars 70 % of a 44 pt band from a 188 pt plot.
        let (_, commands) = render(Chart(Self.sales + [Sale(month: "Apr", amount: 71, kind: "Online"), Sale(month: "May", amount: 64, kind: "Online"), Sale(month: "Jun", amount: 90, kind: "Online")]) { sale in
            BarMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
        }.padding(16))
        let fills = commands.compactMap { command -> CGRect? in
            if case .fillPath(let path, let color, _) = command, color.blue == 1 { return path.boundingRect }
            return nil
        }
        #expect(fills.count == 6)
        let jan = fills[0]
        #expect(abs(jan.minX - 22.6) < 0.05 && abs(jan.width - 30.8) < 0.05 && abs(jan.minY - 125.04) < 0.05 && abs(jan.maxY - 204) < 0.01)
        // Grid: the vertical band edges (dashed) and five horizontal ticks (solid).
        let strokes = commands.compactMap { command -> (CGRect, Bool)? in
            if case .strokePath(let path, let style, _) = command { return (path.boundingRect, !style.dash.isEmpty) }
            return nil
        }
        let verticals = strokes.filter { $0.0.width == 0 }
        let horizontals = strokes.filter { $0.0.height == 0 }
        #expect(verticals.count == 7 && verticals.allSatisfy(\.1) && verticals.map { $0.0.minX } == [16, 60, 104, 148, 192, 236, 280])
        #expect(horizontals.count == 5 && horizontals.allSatisfy { !$0.1 } && horizontals.map { $0.0.minY } == [204, 157, 110, 63, 16])
        // Labels: the months centred under their bands 5 below the plot, the values 4 after it.
        let texts = commands.compactMap { command -> (String, CGPoint)? in
            if case .drawText(let string, _, let origin, _) = command { return (string, origin) }
            return nil
        }
        #expect(texts.map(\.0) == ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "0", "25", "50", "75", "100"])
        #expect(texts[0].1.x < 38 && texts[0].1.x > 28 && abs(texts[0].1.y - (209 + 11)) < 1)   // baseline of a 14 pt line box
        #expect(texts[6].1.x == 284 && abs(texts[10].1.y - (16 - 7 + 11)) < 1)
    }

    @Test func horizontalBarsRuleAndAnnotation() {
        // charts/scales: inside labels, 4 pt corners at the value end only, a 0...100 domain
        // whose "100" label is dropped at the edge; the legend hidden.
        let (_, commands) = render(Chart(Self.stores) { sale in
            BarMark(x: .value("Sales", sale.amount), y: .value("Month", sale.month))
                .foregroundStyle(by: .value("Kind", sale.kind))
                .cornerRadius(4)
        }
        .chartXScale(domain: 0...100)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartLegend(.hidden)
        .padding(16))
        #expect(drawn(commands) == ["0", "25", "50", "75", "Jan", "Feb", "Mar"])   // no "100" at the edge, no legend
        let bars = commands.compactMap { command -> Path? in
            if case .fillPath(let path, _, _) = command { return path }
            return nil
        }
        #expect(bars.count == 3)
        // The plot is 288 wide, 188 tall: three bands of 62.67, the bar in the 42.67 under the label.
        let jan = bars[0].boundingRect
        #expect(abs(jan.minX - 16) < 0.01 && abs(jan.maxX - (16 + 0.3 * 288)) < 0.01 && abs(jan.height - 0.7 * (188 / 3 - 20)) < 0.01)
        // A rule with an annotation above it at the leading edge.
        let (_, ruled) = render(Chart {
            ForEach(Self.sales) { sale in AreaMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount)) }
            RuleMark(y: .value("Average", 60)).foregroundStyle(.red).annotation(position: .top, alignment: .leading) { Text("Average").font(.caption) }
        }.chartXAxis(.hidden).padding(16))
        let rule = ruled.compactMap { command -> (CGRect, StrokeStyle)? in
            if case .strokePath(let path, let style, let color) = command, color.red == 1 { return (path.boundingRect, style) }
            return nil
        }
        #expect(rule.count == 1 && rule[0].1.lineWidth == 2 && rule[0].1.lineCap == .round && abs(rule[0].0.minY - (224 - 0.6 * 208)) < 0.01 && rule[0].0.minX == 16 && rule[0].0.maxX == 280)
        let annotation = ruled.compactMap { command -> CGPoint? in
            if case .drawText("Average", _, let origin, _) = command { return origin }
            return nil
        }
        #expect(annotation.count == 1 && annotation[0].x == 16 && annotation[0].y < rule[0].0.minY - 4)
        #expect(!ruled.contains { if case .strokePath(_, let style, _) = $0 { return !style.dash.isEmpty } else { return false } })   // no vertical grid with the x axis hidden
    }

    @Test func legendAndProxy() {
        let (_, commands) = render(Chart(Self.sales + Self.stores) { sale in
            PointMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount)).foregroundStyle(by: .value("Kind", sale.kind))
        }.padding(16))
        // Two 8 pt swatches in the legend row 8 below the canvas; six 8 pt points.
        let ellipses = commands.compactMap { command -> CGRect? in
            if case .fillPath(let path, _, _) = command, abs(path.boundingRect.width - 8) < 0.01 { return path.boundingRect }
            return nil
        }
        #expect(ellipses.count == 8)
        let legendSwatch = ellipses.max { $0.minY < $1.minY }!
        #expect(legendSwatch.minX == 16 && abs(legendSwatch.midY - (224 - 7)) < 1)
        #expect(drawn(commands).suffix(2) == ["Online", "Store"])
        var captured: ChartProxy?
        let (_, _) = render(Chart(Self.sales) { sale in
            BarMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
        }.chartOverlay { proxy in _ProxyCapture(proxy: proxy) { captured = $0 } }.padding(16))
        let proxy = try! #require(captured)
        #expect(proxy.plotSize.height == 188)
        #expect(proxy.position(forX: "Feb").map { abs($0 - proxy.plotSize.width / 2) < 0.01 } == true)
        #expect(proxy.position(forY: 50.0).map { abs($0 - 94) < 0.01 } == true)
        let month: String? = proxy.value(atX: 10)
        #expect(month == "Jan")
    }

    @Test func axisMarksCustomise() {
        let (_, commands) = render(Chart(Self.sales) { sale in
            BarMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
        }
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine(); AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))) } }
        .chartXAxis { AxisMarks { AxisValueLabel() } }
        .padding(16))
        #expect(drawn(commands) == ["Jan", "Feb", "Mar", "0.0", "50.0", "100.0"])
        // No grid lines on the x axis (labels only), three on the y axis.
        let strokes = commands.filter { if case .strokePath = $0 { return true } else { return false } }
        #expect(strokes.count == 3)
    }
}

/// Hands the proxy to the test.
struct _ProxyCapture: View {
    let proxy: ChartProxy
    let capture: (ChartProxy) -> Void
    var body: some View {
        capture(proxy)
        return Color.clear
    }
}

/// A text engine with the macOS 11 pt metrics the chart's labels use (digits 6.4 wide, the
/// month names as measured, 14 pt line boxes with the baseline at 11) and 10 pt captions.
final class MetricsTextEngine: TextEngine {
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let string = runs.map(\.string).joined()
        let size = runs.first?.font.size ?? 13
        let widths: [String: CGFloat] = ["Jan": 18.6, "Feb": 19.4, "Mar": 20.4, "Apr": 18.3, "May": 21.6, "Jun": 18.6, "Online": 33.5, "Store": 28.2, "Average": 38.9]
        let w = widths[string] ?? CGFloat(string.count) * size * 0.58
        let height: CGFloat = size <= 10 ? 12 : 14
        let baseline: CGFloat = size <= 10 ? 9.5 : 11
        let line = TextLayout.Line(range: string.startIndex..<string.endIndex, width: w, baseline: baseline, fragments: [TextLayout.Fragment(text: string, run: 0, x: 0, width: w)])
        return TextLayout(size: CGSize(width: w, height: height), firstBaseline: baseline, lastBaseline: baseline, lines: [line])
    }

    func metrics(for font: ResolvedFont) -> FontMetrics {
        FontMetrics(lineHeight: font.size <= 10 ? 12 : 14, spacingBelow: 0, spacingAbove: 0, textToText: 0)
    }
}
#endif
