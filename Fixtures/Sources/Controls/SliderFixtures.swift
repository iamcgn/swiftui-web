// Slider fixtures: values along the track, ranges and steps, labels, widths, disabled, and a
// behaviour fixture whose knob follows the model.
import SwiftUI
import FixtureKit

/// Drives `slider/steps`.
@Observable
public final class SliderModel {
    public var value = 0.25
    public init() {}
}

public enum SliderFixtures {
    public static let basic = Fixture("slider/basic", size: CGSize(width: 320, height: 300)) {
        VStack(spacing: 12) {
            Slider(value: .constant(0.5)).probe("half")
            Slider(value: .constant(0)).probe("zero")
            Slider(value: .constant(1)).probe("full")
            Slider(value: .constant(25), in: 0...100, step: 5).probe("stepped")
            Slider(value: .constant(0.5)) { Text("Volume") }.probe("labelled")
            Slider(value: .constant(0.5), in: 0...1) { Text("Volume") } minimumValueLabel: { Text("Min").probe("min") } maximumValueLabel: { Text("Max").probe("max") }.probe("minMax")
            Slider(value: .constant(0.5)).frame(width: 120).probe("narrow")
            Slider(value: .constant(0.5)).disabled(true).probe("disabled")
            HStack(spacing: 8) {
                Text("Row").probe("rowText")
                Slider(value: .constant(0.5)).probe("rowSlider")
            }
            .probe("row")
        }
        .probe("stack")
    }

    public static let steps = Fixture(
        "slider/steps", size: CGSize(width: 320, height: 100),
        model: { SliderModel() },
        steps: [
            FixtureStep("half") { $0.value = 0.5 },
            FixtureStep("full") { $0.value = 1 },
            FixtureStep("zero") { $0.value = 0 },
        ]
    ) { model in
        HStack(spacing: 12) {
            Slider(value: Binding(get: { model.value }, set: { model.value = $0 })).probe("slider")
            Text("\(Int((model.value * 100).rounded()))").probe("echo")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [basic, steps]
}
