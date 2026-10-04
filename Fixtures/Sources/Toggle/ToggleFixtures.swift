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
            #if !os(iOS)   // macOS-only API (true on macOS, wasm and Linux); the iOS builds render only ios/ fixtures
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

/// A source for `Toggle(sources:isOn:)`.
public struct ToggleSource {
    public var value: Binding<Bool>
    public init(_ value: Binding<Bool>) { self.value = value }
}

extension ToggleFixtures {
    /// Mixed state from disagreeing sources, control sizes, tints. Out of the golden set: macOS
    /// 26.6 draws a 14 pt checkbox in a white bezel and a 22 pt switch with a round knob (the
    /// 26.2 goldens above have 16 and 24 with a pill knob), and an inactive window shows no tint;
    /// its measurements are in Docs/elements/Toggle.md ("macOS 26.6").
    public static let looks = Fixture("toggle/looks", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: .constant(true)).probe("on")
            Toggle("Mixed", sources: [ToggleSource(.constant(true)), ToggleSource(.constant(false))], isOn: \.value).probe("mixed")
            Toggle("Agree", sources: [ToggleSource(.constant(true)), ToggleSource(.constant(true))], isOn: \.value).probe("sourcesOn")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Mini", isOn: .constant(true)).controlSize(.mini).probe("mini")
                Toggle("Small", isOn: .constant(true)).controlSize(.small).probe("small")
                Toggle("Large", isOn: .constant(true)).controlSize(.large).probe("large")
            }
            .probe("sizes")
            HStack(spacing: 8) {
                Toggle("Mini", isOn: .constant(true)).toggleStyle(.switch).controlSize(.mini).probe("switchMini")
                Toggle("Small", isOn: .constant(true)).toggleStyle(.switch).controlSize(.small).probe("switchSmall")
            }
            .probe("switchSizes")
            Toggle("Large", isOn: .constant(true)).toggleStyle(.switch).controlSize(.large).probe("switchLarge")
            Toggle("Tinted", isOn: .constant(true)).tint(.red).probe("tinted")
            Toggle("Tinted", isOn: .constant(true)).toggleStyle(.switch).tint(.red).probe("tintedSwitch")
        }
        .probe("stack")
    }
}
