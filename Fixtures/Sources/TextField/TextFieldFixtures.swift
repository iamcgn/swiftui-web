// TextField fixtures: the macOS rounded-border field (default), plain and square-border
// styles, placeholder vs text, secure fields, labels, sizing in stacks, disabled, and a
// behaviour fixture whose text follows the model.
import SwiftUI
import FixtureKit

/// Drives `textfield/steps`.
@Observable
public final class TextFieldModel {
    public var text = ""
    public init() {}
}

public enum TextFieldFixtures {
    /// Field geometry: default style with placeholder and with text, labels, secure fields.
    public static let basic = Fixture("textfield/basic", size: CGSize(width: 320, height: 260)) {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Placeholder", text: .constant("")).probe("empty")
            TextField("Placeholder", text: .constant("Hello")).probe("filled")
            TextField("Name", text: .constant("Hello")).labelsHidden().probe("hidden")
            SecureField("Password", text: .constant("")).probe("secureEmpty")
            SecureField("Password", text: .constant("Hello")).probe("secureFilled")
            TextField("Placeholder", text: .constant("Hello")).disabled(true).probe("disabled")
            TextField("Placeholder", text: .constant("Hello")).frame(width: 120).probe("narrow")
        }
        .probe("stack")
    }

    /// Styles and layout next to other controls.
    public static let styles = Fixture("textfield/styles", size: CGSize(width: 320, height: 260)) {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.roundedBorder).probe("rounded")
            TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.plain).probe("plain")
            #if !targetEnvironment(macCatalyst)   // macOS-only API; the Catalyst build renders only ios/ fixtures
            TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.squareBorder).probe("square")
            #endif
            TextField("Placeholder", text: .constant("")).textFieldStyle(.plain).probe("plainEmpty")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Name").probe("rowLabel")
                TextField("Placeholder", text: .constant("Hello")).probe("rowField")
                Button("OK") {}.probe("rowButton")
            }
            .probe("row")
            HStack(spacing: 8) {
                TextField("A", text: .constant("Hello")).probe("halfA")
                TextField("B", text: .constant("Hello")).probe("halfB")
            }
            .probe("halves")
        }
        .probe("stack")
    }

    /// Behaviour: the field shows the model's text; a text next to it echoes it.
    public static let steps = Fixture(
        "textfield/steps", size: CGSize(width: 320, height: 120),
        model: { TextFieldModel() },
        steps: [
            FixtureStep("typed") { $0.text = "Hello" },
            FixtureStep("cleared") { $0.text = "" },
        ]
    ) { model in
        HStack(spacing: 12) {
            TextField("Placeholder", text: Binding(get: { model.text }, set: { model.text = $0 })).frame(width: 160).probe("field")
            Text(model.text.isEmpty ? "Off" : "On").probe("echo")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [basic, styles, steps]
}
