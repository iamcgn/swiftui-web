// Swift Charts fixtures (sw-frameworks, Docs/elements/Charts.md): the marks apps reach for first
// with the default axes and legend, measured against Apple's Charts on macOS. The harness
// builds these against the real framework; the web build against `Sources/Charts`.
import SwiftUI
import FixtureKit
#if canImport(Charts)
import Charts

public enum ChartFixtures {
    struct Sale: Identifiable {
        let id = UUID()
        let month: String
        let amount: Double
        let kind: String
    }

    static let sales: [Sale] = [
        Sale(month: "Jan", amount: 42, kind: "Online"), Sale(month: "Feb", amount: 58, kind: "Online"),
        Sale(month: "Mar", amount: 35, kind: "Online"), Sale(month: "Apr", amount: 71, kind: "Online"),
        Sale(month: "May", amount: 64, kind: "Online"), Sale(month: "Jun", amount: 90, kind: "Online"),
    ]

    static let stores: [Sale] = [
        Sale(month: "Jan", amount: 30, kind: "Store"), Sale(month: "Feb", amount: 25, kind: "Store"),
        Sale(month: "Mar", amount: 48, kind: "Store"), Sale(month: "Apr", amount: 40, kind: "Store"),
        Sale(month: "May", amount: 52, kind: "Store"), Sale(month: "Jun", amount: 45, kind: "Store"),
    ]

    /// Bars over a nominal x axis and the default quantitative y axis on the trailing edge.
    public static let bar = Fixture("charts/bar", size: CGSize(width: 320, height: 240)) {
        Chart(sales) { sale in
            BarMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
        }
        .padding(16)
        .probe("chart")
    }

    /// Two line series coloured by their kind with points, and the legend the series make.
    public static let line = Fixture("charts/line", size: CGSize(width: 320, height: 240)) {
        Chart(sales + stores) { sale in
            LineMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
                .foregroundStyle(by: .value("Kind", sale.kind))
            PointMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
                .foregroundStyle(by: .value("Kind", sale.kind))
        }
        .padding(16)
        .probe("chart")
    }

    /// An area, a rule at the average with an annotation, the x axis hidden.
    public static let area = Fixture("charts/area", size: CGSize(width: 320, height: 240)) {
        Chart {
            ForEach(sales) { sale in
                AreaMark(x: .value("Month", sale.month), y: .value("Sales", sale.amount))
            }
            RuleMark(y: .value("Average", 60))
                .foregroundStyle(.red)
                .annotation(position: .top, alignment: .leading) {
                    Text("Average").font(.caption).foregroundStyle(.red)
                }
        }
        .chartXAxis(.hidden)
        .padding(16)
        .probe("chart")
    }

    /// Horizontal bars with rounded corners, a fixed x domain, the y axis leading and the legend hidden.
    public static let scales = Fixture("charts/scales", size: CGSize(width: 320, height: 240)) {
        Chart(stores) { sale in
            BarMark(x: .value("Sales", sale.amount), y: .value("Month", sale.month))
                .foregroundStyle(by: .value("Kind", sale.kind))
                .cornerRadius(4)
        }
        .chartXScale(domain: 0...100)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartLegend(.hidden)
        .padding(16)
        .probe("chart")
    }

    public static let all: [Fixture] = [bar, line, area, scales]
}
#else
public enum ChartFixtures {
    public static let all: [Fixture] = []
}
#endif
