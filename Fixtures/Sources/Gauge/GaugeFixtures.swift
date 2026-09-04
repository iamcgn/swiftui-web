// Gauge fixtures: the default (linear capacity) gauge with its label forms, bounds and sizing,
// and the accessory styles (linear, linear capacity, circular, circular capacity).
import SwiftUI
import FixtureKit

public enum GaugeFixtures {
    public static let basic = Fixture("gauge/basic", size: CGSize(width: 320, height: 560)) {
        VStack(spacing: 14) {
            Gauge(value: 0.4) { Text("Battery") }.probe("bare")
            Gauge(value: 0.6) { Text("Level") } currentValueLabel: { Text("60%") }.probe("value")
            Gauge(value: 0.3) { Text("Range") } currentValueLabel: { Text("30") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
                .probe("bounds")
            Gauge(value: 25, in: 0...50) { Text("Total") }.probe("total")
            Gauge(value: 0.5) { Text("Narrow") }.frame(width: 120).probe("narrow")
            Gauge(value: 0.7) { Text("Tinted") }.tint(.red).probe("tinted")
            Gauge(value: 0.4) { Text("Cap") }.gaugeStyle(.linearCapacity).probe("capacity")
            Gauge(value: 0.8) { Text("Hidden") }.labelsHidden().probe("hidden")
        }
        .padding(20)
        .probe("stack")
    }

    public static let accessory = Fixture("gauge/accessory", size: CGSize(width: 320, height: 380)) {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Gauge(value: 0.4) { Text("A") } currentValueLabel: { Text("40") }.gaugeStyle(.accessoryCircular).probe("circular")
                Gauge(value: 0.4) { Text("B") } currentValueLabel: { Text("40") }.gaugeStyle(.accessoryCircularCapacity).probe("circularCapacity")
                Gauge(value: 0.3) { Text("C") } currentValueLabel: { Text("30") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
                    .gaugeStyle(.accessoryCircular).probe("circularBounds")
                Gauge(value: 0.4) { Text("D") }.gaugeStyle(.accessoryCircular).probe("circularBare")
            }
            .probe("circulars")
            Gauge(value: 0.4) { Text("Level") } currentValueLabel: { Text("40") }.gaugeStyle(.accessoryLinear).probe("linear")
            Gauge(value: 0.4) { Text("Level") } currentValueLabel: { Text("40") }.gaugeStyle(.accessoryLinearCapacity).probe("linearCapacity")
            Gauge(value: 0.3) { Text("Range") } currentValueLabel: { Text("30") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
                .gaugeStyle(.accessoryLinear).probe("linearBounds")
            Gauge(value: 0.3) { Text("Range") } currentValueLabel: { Text("30") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
                .gaugeStyle(.accessoryLinearCapacity).probe("linearCapacityBounds")
            Gauge(value: 0.6) { Text("Bare") }.gaugeStyle(.accessoryLinear).probe("linearBare")
        }
        .padding(20)
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, accessory]
}
