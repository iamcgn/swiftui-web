// Toggle fixtures: the macOS checkbox (default), switch and button styles, label alignment,
// hidden labels, the disabled look, and a behaviour fixture driven by a model.
import SwiftUI
import FixtureKit

/// Drives `toggle/steps`.
@Observable
public final class ToggleModel {
    public var isOn = false
    public init() {}
}

public enum ToggleFixtures {
    /// Checkbox geometry: control, label spacing, baseline alignment with plain text, hidden
    /// label, disabled appearance.
    public static let basic = Fixture("toggle/basic", size: CGSize(width: 320, height: 240)) {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: .constant(true)).probe("on")
            Toggle("Enabled", isOn: .constant(false)).probe("off")
            Toggle(isOn: .constant(true)) { Text("Hg").probe("customText") }.probe("custom")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Hg", isOn: .constant(true)).probe("baselineToggle")
                Text("Hg").probe("baselineText")
            }
            .probe("baselineRow")
            Toggle("Enabled", isOn: .constant(true)).labelsHidden().probe("hidden")
            Toggle("Enabled", isOn: .constant(true)).disabled(true).probe("disabled")
            Toggle("Enabled", isOn: .constant(false)).disabled(true).probe("disabledOff")
        }
        .probe("stack")
    }

    /// Switch, button and explicit checkbox styles; a switch next to a bordered button.
    public static let styles = Fixture("toggle/styles", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch).probe("switchOn")
            Toggle("Enabled", isOn: .constant(false)).toggleStyle(.switch).probe("switchOff")
            Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch).labelsHidden().probe("switchHidden")
            Toggle("Enabled", isOn: .constant(true)).toggleStyle(.button).probe("buttonOn")
            Toggle("Enabled", isOn: .constant(false)).toggleStyle(.button).probe("buttonOff")
            #if !targetEnvironment(macCatalyst)   // macOS-only API; the Catalyst build renders only ios/ fixtures
            Toggle("Enabled", isOn: .constant(true)).toggleStyle(.checkbox).probe("checkbox")
            #endif
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch).probe("rowSwitch")
                Button("OK") {}.probe("rowButton")
                Toggle("Enabled", isOn: .constant(true)).probe("rowCheckbox")
            }
            .probe("row")
        }
        .probe("stack")
    }

    /// Behaviour: the checkbox and a text follow the model.
    public static let steps = Fixture(
        "toggle/steps", size: CGSize(width: 240, height: 120),
        model: { ToggleModel() },
        steps: [
            FixtureStep("on") { $0.isOn = true },
            FixtureStep("off") { $0.isOn = false },
        ]
    ) { model in
        HStack(spacing: 12) {
            Toggle("Enabled", isOn: Binding(get: { model.isOn }, set: { model.isOn = $0 })).probe("toggle")
            Text(model.isOn ? "On" : "Off").probe("state")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [basic, styles, steps]
}
