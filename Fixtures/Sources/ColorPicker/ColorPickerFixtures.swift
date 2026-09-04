// ColorPicker fixtures: the macOS colour well with its label, opacity support, translucent
// colours, hidden labels, the disabled look, custom labels and baseline alignment, form rows,
// sizing, and a behaviour fixture whose colour follows the model.
import SwiftUI
import FixtureKit

/// Drives `colorpicker/steps`.
@Observable
public final class ColorPickerModel {
    public var color: Color = .red
    public init() {}
}

public enum ColorPickerFixtures {
    public static let basic = Fixture("colorpicker/basic", size: CGSize(width: 320, height: 220)) {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker("Accent", selection: .constant(.red)).probe("red")
            ColorPicker("Tint", selection: .constant(.blue), supportsOpacity: false).probe("opaque")
            ColorPicker("Accent", selection: .constant(Color(red: 0.2, green: 0.6, blue: 0.4, opacity: 0.5))).probe("translucent")
            ColorPicker("Accent", selection: .constant(.red)).labelsHidden().probe("hidden")
            ColorPicker("Accent", selection: .constant(.red)).disabled(true).probe("disabled")
        }
        .probe("stack")
    }

    public static let labels = Fixture("colorpicker/labels", size: CGSize(width: 320, height: 160)) {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker(selection: .constant(.green)) { Text("Tint").foregroundColor(.secondary).probe("customText") }.probe("custom")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ColorPicker("Hg", selection: .constant(.orange)).probe("baselinePicker")
                Text("Hg").probe("baselineText")
            }
            .probe("baselineRow")
            HStack(spacing: 8) {
                Text("Above").probe("rowText")
                ColorPicker("Accent", selection: .constant(.purple)).probe("rowPicker")
            }
            .probe("row")
        }
        .probe("stack")
    }

    public static let form = Fixture("colorpicker/form", size: CGSize(width: 320, height: 200)) {
        Form {
            ColorPicker("Accent", selection: .constant(.red)).probe("accent")
            ColorPicker("Tint", selection: .constant(.blue), supportsOpacity: false).probe("tint")
            Toggle("Enabled", isOn: .constant(true)).probe("toggle")
        }
        .probe("form")
    }

    public static let sized = Fixture("colorpicker/sized", size: CGSize(width: 320, height: 200)) {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker("Accent", selection: .constant(.red)).frame(width: 240).probe("wide")
            HStack(spacing: 0) {
                ColorPicker("Accent", selection: .constant(.red)).probe("leading")
                Spacer()
            }
            .probe("spaced")
        }
        .probe("stack")
    }

    public static let steps = Fixture(
        "colorpicker/steps", size: CGSize(width: 240, height: 100),
        model: { ColorPickerModel() },
        steps: [
            FixtureStep("blue") { $0.color = .blue },
            FixtureStep("clear") { $0.color = .clear },
        ]
    ) { model in
        ColorPicker("Accent", selection: Binding(get: { model.color }, set: { model.color = $0 })).probe("picker")
    }

    public static let all: [Fixture] = [basic, labels, form, sized, steps]
}
