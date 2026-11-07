// Chart descriptors (API/AccessibilityCharts.swift): axes, series and points as the Swift Charts
// examples describe their charts, and the modifier making the descriptor only when asked.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Counter { var made = 0 }

@MainActor private struct SalesChart: View, AXChartDescriptorRepresentable {
    let counter: Counter
    var body: some View { Color.blue.frame(width: 40, height: 20).accessibilityChartDescriptor(self) }

    func makeChartDescriptor() -> AXChartDescriptor {
        counter.made += 1
        let x = AXCategoricalDataAxisDescriptor(title: "Days", categoryOrder: ["Mon", "Tue"])
        let y = AXNumericDataAxisDescriptor(title: "Sales", range: 0...10, gridlinePositions: [5]) { "\(Int($0)) sold" }
        let series = AXDataSeriesDescriptor(name: "Store", isContinuous: false, dataPoints: [
            .init(x: "Mon", y: 3, label: "Monday"),
            .init(x: "Tue", y: 7, additionalValues: [.category("busy")]),
        ])
        return AXChartDescriptor(title: "Sales per day", summary: nil, xAxis: x, yAxis: y, series: [series])
    }
}

@Suite @MainActor struct AccessibilityChartTests {
    @Test func descriptorParts() throws {
        let counter = Counter()
        let chart = SalesChart(counter: counter)
        let descriptor = chart.makeChartDescriptor()
        #expect(descriptor.title == "Sales per day" && descriptor.additionalAxes.isEmpty)
        #expect((descriptor.xAxis as? AXCategoricalDataAxisDescriptor)?.categoryOrder == ["Mon", "Tue"])
        let y = try #require(descriptor.yAxis)
        #expect(y.valueDescriptionProvider(4) == "4 sold" && y.scaleType == .linear)
        let points = descriptor.series[0].dataPoints
        #expect(points[0].xValue == .category("Mon") && points[0].yValue == 3 && points[0].label == "Monday")
        #expect(points[1].additionalValues == [.category("busy")])
        #expect(AXDataPoint(x: 2.5).xValue == .number(2.5))
    }

    @Test func modifierMakesTheDescriptorOnRequest() {
        let counter = Counter()
        let runtime = Runtime()
        runtime.mount(SalesChart(counter: counter))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(counter.made == 0)
        let modifier = _AccessibilityChartModifier(representable: SalesChart(counter: counter))
        #expect(modifier.descriptor().title == "Sales per day" && counter.made == 1)
    }
}
#endif
