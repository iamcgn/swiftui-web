// Stepper fixtures: label forms, ranges, hidden labels, custom labels, closures, rows, disabled,
// and a behaviour fixture whose echo text follows the model.
import SwiftUI
import FixtureKit

/// Drives `stepper/steps`.
@Observable
public final class StepperModel {
    public var count = 0
    public init() {}
}

public enum StepperFixtures {
    public static let basic = Fixture("stepper/basic", size: CGSize(width: 320, height: 320)) {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Count", value: .constant(1)).probe("basic")
            Stepper("Count", value: .constant(1), in: 0...10, step: 2).probe("ranged")
            Stepper("Count", value: .constant(1)).labelsHidden().probe("hidden")
            Stepper(value: .constant(1)) { Label("Count", image: "icon") }.probe("labelStepper")
            Stepper("Count", onIncrement: {}, onDecrement: {}).probe("closures")
            HStack(spacing: 8) {
                Text("Row").probe("rowText")
                Stepper("Count", value: .constant(1)).labelsHidden().probe("rowStepper")
                Button("OK") {}.probe("rowButton")
            }
            .probe("row")
            Stepper("Count", value: .constant(1)).disabled(true).probe("disabled")
            Stepper("Count", value: .constant(1)).frame(width: 200).probe("fixed")
        }
        .probe("stack")
    }

    public static let steps = Fixture(
        "stepper/steps", size: CGSize(width: 320, height: 80),
        model: { StepperModel() },
        steps: [
            FixtureStep("one") { $0.count = 1 },
            FixtureStep("two") { $0.count = 2 },
            FixtureStep("reset") { $0.count = 0 },
        ]
    ) { model in
        HStack(spacing: 12) {
            Stepper("Count", value: Binding(get: { model.count }, set: { model.count = $0 })).probe("stepper")
            Text("\(model.count)").probe("echo")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [basic, steps]
}
