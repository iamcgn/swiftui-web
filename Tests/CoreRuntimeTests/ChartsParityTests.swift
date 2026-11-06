// Swift Charts API the Swift Charts Examples app uses (Apps/upstream/Swift-Charts-Examples):
// `Plot`, masks, spans across the plot, an app's own symbol shapes and symbol views, gradient
// colour scales, axis marks built with conditions, bins, and the plot frame as an anchor.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Charts

#if !os(WASI)
@Suite @MainActor struct ChartsParityTests {
    private func records<C: ChartContent>(@ChartContentBuilder _ content: () -> C) -> [_MarkRecord] {
        var out: [_MarkRecord] = []
        content()._collect(into: &out)
        return out
    }

    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 240)) -> [DisplayCommand] {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime.render(scale: 2).commands
    }

    /// A square drawn in the middle three quarters of its unit rectangle.
    struct Diamondish: ChartSymbolShape {
        func path(in rect: CGRect) -> Path { Path(rect) }
        var perceptualUnitRect: CGRect { CGRect(x: 0.125, y: 0.125, width: 0.75, height: 0.75) }
    }

    @Test func plotGroupsAndMaskRestyles() {
        let out = records {
            Plot {
                BarMark(x: .value("Day", "Mon"), y: .value("Steps", 4))
                BarMark(x: .value("Day", "Tue"), y: .value("Steps", 6))
            }
            .accessibilityLabel("Steps")
            .accessibilityValue("\(6.0, specifier: "%.1f") k")
            RectangleMark(xStart: .value("x", 0), xEnd: .value("x", 10))
                .foregroundStyle(Color.red)
                .mask {
                    AreaMark(x: .value("x", 1), y: .value("y", 2)).opacity(0.4)
                    LineMark(x: .value("x", 1), y: .value("y", 2))
                }
        }
        #expect(out.count == 4 && out[0].kind == .bar && out[1].x == .category("Tue"))
        // The mask's marks take the masked content's style and keep their own opacity.
        #expect(out[2].kind == .area && out[2].style != nil && abs(out[2].opacity - 0.4) < 1e-9)
        #expect(out[3].kind == .line && out[3].style != nil && out[3].opacity == 1)
        #expect(InterpolationMethod.catmullRom.description == "catmullRom")
    }

    @Test func aSpanCoversThePlotsHeight() {
        let commands = render(Chart {
            RectangleMark(xStart: .value("x", 2.0), xEnd: .value("x", 4.0)).foregroundStyle(Color.red)
            PointMark(x: .value("x", 0.0), y: .value("y", 0.0))
            PointMark(x: .value("x", 10.0), y: .value("y", 10.0))
        })
        let span = commands.compactMap { command -> CGRect? in
            if case .fillPath(let path, let color, _) = command, color.red == 1, color.green < 0.3 { return path.boundingRect }
            return nil
        }.first
        let rect = try! #require(span)
        #expect(rect.width > 20 && rect.height > 150)
    }

    @Test func customSymbolsAndSymbolViews() {
        let out = records {
            LineMark(x: .value("x", 1), y: .value("y", 2)).symbol(Diamondish())
            LineMark(x: .value("x", 2), y: .value("y", 3)).symbol(.square)
            PointMark(x: .value("x", 3), y: .value("y", 4)).symbol { Circle().frame(width: 6) }
            PointMark(x: .value("x", 4), y: .value("y", 5)).symbol(Circle().strokeBorder(lineWidth: 2))
        }
        #expect(out[0].customSymbol != nil && out[0].symbolSize != nil)
        #expect(out[1].customSymbol == nil && out[1].symbol == .square)
        #expect(out[2].symbolView != nil && out[3].symbolView != nil)
        // The custom path fills its perceptual rectangle: an 8 pt symbol draws the shape over
        // 8 / 0.75 points around the same centre.
        let symbol = try! #require(out[0].customSymbol)
        let drawn = symbol.path(CGRect(x: 0, y: 0, width: 8, height: 8)).boundingRect
        #expect(abs(drawn.width - 8 / 0.75) < 0.01 && abs(drawn.midX - 4) < 0.01)
        #expect(BasicChartSymbolShape.circle.perceptualUnitRect.width == 1)
    }

    @Test func gradientScaleColoursByValue() {
        let commands = render(Chart([0, 5, 10], id: \.self) { value in
            BarMark(x: .value("Index", "\(value)"), y: .value("Count", 1)).foregroundStyle(by: .value("Level", value))
        }.chartForegroundStyleScale(range: Gradient(colors: [.white, .black])).chartLegend(.hidden))
        let fills = commands.compactMap { command -> RGBA? in
            if case .fillPath(_, let color, _) = command, color.alpha == 1, color.red == color.green, color.green == color.blue { return color }
            return nil
        }
        // White for the smallest value, black for the largest, mid grey between.
        #expect(fills.count >= 3)
        #expect(fills.contains { $0.red == 1 } && fills.contains { $0.red == 0 } && fills.contains { abs($0.red - 0.5) < 0.01 })
    }

    @Test func axisMarksTakeConditionsAndStyles() {
        let marks = AxisMarks(preset: .inset, values: .automatic(desiredCount: 4)) { value in
            if value.index % 2 == 0 {
                AxisGridLine().foregroundStyle(Color.red)
                AxisValueLabel()
            } else {
                AxisTick()
            }
            switch value.index {
            case 1: AxisValueLabel("One")
            default: AxisGridLine()
            }
        }
        #expect(marks.preset == .inset)
        let part = AxisGridLine().foregroundStyle(.gray)._part
        #expect(part.color == .gray)
    }

    @Test func numberBins() {
        let bins = NumberBins(range: 0.0...10.0, count: 5)
        #expect(bins.count == 5 && bins[1].lowerBound == 2 && bins[1].upperBound == 4)
        #expect(bins.index(for: -3) == 0 && bins.index(for: 3.9) == 1 && bins.index(for: 4) == 2 && bins.index(for: 10) == 4 && bins.index(for: 99) == 4)
        #expect(NumberBins(size: 3.0, range: 0.0...7.0).thresholds == [0, 3, 6, 9])
        #expect(NumberBins(thresholds: [5.0, 1.0, 3.0]).thresholds == [1, 3, 5])
    }

    @Test func plotFrameIsAnAnchor() {
        var captured: ChartProxy?
        _ = render(Chart([1, 2, 3], id: \.self) { n in
            BarMark(x: .value("N", "\(n)"), y: .value("V", n))
        }.chartOverlay { proxy in _ProxyCapture(proxy: proxy) { captured = $0 } }.padding(16))
        let proxy = try! #require(captured)
        let anchor = proxy.plotAreaFrame
        // In the chart's own coordinates the anchor is the plot rectangle; in the root's it is
        // moved by the padding.
        #expect(anchor.rootValue.size == proxy.plotSize && anchor.rootValue.minX >= 16 && anchor.rootValue.minY >= 16)
        #expect(anchor.value(relativeTo: CGPoint(x: 16, y: 16)) == proxy.geometry.plot)
        #expect(proxy.plotFrame == anchor)
    }

    private func middle() -> Date { Date(timeIntervalSince1970: 10) }
    private func middle() -> Double { 10 }

    /// A call that could make a date or a number plots the date (TimeSheetBar's `getEventMiddle`,
    /// ambiguous on wasm where `CGFloat` is `Double`).
    @Test func aDateIsPreferredWhenACallCouldBeEither() {
        let out = records { RuleMark(x: .value("Middle", middle())) }
        #expect(out[0].x == .date(Date(timeIntervalSince1970: 10)))
    }

    @Test func decimalsPlot() {
        let out = records { BarMark(x: .value("Day", "Mon"), y: .value("Price", Decimal(string: "12.5")!)) }
        #expect(out[0].y == .number(12.5))
    }
}

/// SwiftUI API the app uses outside its charts.
@Suite @MainActor struct ChartsAppSwiftUITests {
    @Test func textSpecifiersAndFormats() {
        let key: LocalizedStringKey = "Bar Width: \(7.0, specifier: "%.1f"), \(3, specifier: "%02d")"
        #expect(key.key == "Bar Width: 7.0, 03")
        let formatted: LocalizedStringKey = "\(Date(timeIntervalSince1970: 0), format: Date.FormatStyle.dateTime.year())"
        #expect(formatted.key == Date(timeIntervalSince1970: 0).formatted(Date.FormatStyle.dateTime.year()))
    }

    @Test func bindingAnimationCarriesItsTransaction() {
        var value = 1
        let binding = Binding(get: { value }, set: { value = $0 }).animation(.easeInOut)
        #expect(binding.transaction.animation != nil)
        binding.wrappedValue = 2
        #expect(value == 2)
        #expect(Binding.constant(0).animation(nil).transaction.animation == nil)
    }

    @Test func gradientAndBackgroundAreStyles() {
        let environment = EnvironmentValues()
        let gradient = Gradient(colors: [.red, .blue])
        #expect(gradient.resolveColor(in: environment) == Color.red.resolve(in: environment))
        #expect(AnyShapeStyle(gradient)._resolveGradient(in: CGRect(x: 0, y: 0, width: 10, height: 10), environment: environment).stops.count >= 2)
        #expect(BackgroundStyle().resolveColor(in: environment) == Color(storage: .system(.windowBackground)).resolve(in: environment))
        #expect(Color.white.shadow(.drop(radius: 2)).resolveColor(in: environment) == Color.white.resolve(in: environment))
    }

    @Test func anchorsMoveIntoAReadersCoordinates() {
        let anchor = Anchor<CGRect>(rootRect: CGRect(x: 30, y: 40, width: 100, height: 50))
        #expect(anchor.value(relativeTo: CGPoint(x: 10, y: 15)) == CGRect(x: 20, y: 25, width: 100, height: 50))
        #expect(Anchor<CGPoint>(rootPoint: CGPoint(x: 5, y: 5)).value(relativeTo: CGPoint(x: 5, y: 1)) == CGPoint(x: 0, y: 4))
    }
}
#endif
