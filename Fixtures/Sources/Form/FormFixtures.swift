// Form fixtures: the macOS grouped form (default) with control rows and sections, the columns
// style, plain text and buttons in a form, and a behaviour fixture whose rows change.
import SwiftUI
import FixtureKit

/// Drives `form/steps`.
@Observable
public final class FormModel {
    public var enabled = false
    public var name = ""
    public init() {}
}

public enum FormFixtures {
    /// Control rows: labels in the leading column, controls in the trailing one.
    public static let basic = Fixture("form/basic", size: CGSize(width: 360, height: 320)) {
        Form {
            TextField("Name", text: .constant("Hello")).probe("field")
            Toggle("Enabled", isOn: .constant(true)).probe("toggle")
            Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }.probe("picker")
            Slider(value: .constant(0.5)) { Text("Volume") }.probe("slider")
            Stepper("Count", value: .constant(1)).probe("stepper")
            Button("Save") {}.probe("button")
            Text("Plain").probe("text")
        }
        .probe("form")
    }

    /// Sections with headers and footers, and a segmented picker.
    public static let sections = Fixture("form/sections", size: CGSize(width: 360, height: 360)) {
        Form {
            Section("Account") {
                TextField("Name", text: .constant("Hello")).probe("field")
                Toggle("Enabled", isOn: .constant(false)).probe("toggle")
            }
            .probe("account")
            Section {
                Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }.pickerStyle(.segmented).probe("segmented")
                Text("Plain").probe("text")
            } header: {
                Text("Options").probe("optionsHeader")
            } footer: {
                Text("Footer").probe("optionsFooter")
            }
            .probe("options")
        }
        .probe("form")
    }

    /// Styles: grouped (default), columns, and a form in a fixed frame.
    public static let styles = Fixture("form/styles", size: CGSize(width: 360, height: 360)) {
        VStack(spacing: 8) {
            Form {
                TextField("Name", text: .constant("Hello")).probe("groupedField")
                Toggle("Enabled", isOn: .constant(true)).probe("groupedToggle")
            }
            .formStyle(.grouped)
            .frame(height: 110)
            .probe("grouped")
            Form {
                TextField("Name", text: .constant("Hello")).probe("columnsField")
                Toggle("Enabled", isOn: .constant(true)).probe("columnsToggle")
            }
            .formStyle(.columns)
            .frame(height: 110)
            .probe("columns")
            Form {
                Toggle("Enabled", isOn: .constant(true)).probe("narrowToggle")
            }
            .frame(width: 200, height: 110)
            .probe("narrow")
        }
        .probe("stack")
    }

    /// Behaviour: a toggle row follows the model; a text row appears.
    public static let steps = Fixture(
        "form/steps", size: CGSize(width: 360, height: 200),
        model: { FormModel() },
        steps: [
            FixtureStep("enable") { $0.enabled = true },
            FixtureStep("name") { $0.name = "Hello" },
        ]
    ) { model in
        Form {
            Toggle("Enabled", isOn: Binding(get: { model.enabled }, set: { model.enabled = $0 })).probe("toggle")
            if !model.name.isEmpty { Text(model.name).probe("name") }
            TextField("Name", text: Binding(get: { model.name }, set: { model.name = $0 })).probe("field")
        }
        .probe("form")
    }

    /// The grouped style's constants: section headers, footers and spacing, the picker, stepper
    /// and text rows, a group box inside, a nested columns form (macOS 26.6 lays the grouped form
    /// out as 26.2 did; its slider and button rows carry 26.6's 20 pt controls and are recorded in
    /// Docs/elements/Form.md instead of measured here).
    public static let grouped = Fixture("form/grouped", size: CGSize(width: 360, height: 560)) {
        Form {
            Section {
                TextField("Name", text: .constant("Hello")).probe("field")
                Toggle("Enabled", isOn: .constant(true)).probe("toggle")
                Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Pear").tag(2) }.probe("picker")
            } header: {
                Text("Account").probe("header")
            } footer: {
                Text("Your details.").probe("footer")
            }
            Section("Levels") {
                Stepper("Count: 3", value: .constant(3)).probe("stepper")
                Text("Plain row").probe("text")
            }
            Section {
                GroupBox("Box") { Text("Boxed").probe("boxed") }.probe("box")
                Form { Toggle("Nested", isOn: .constant(false)).probe("nestedToggle") }.formStyle(.columns).probe("nested")
            }
        }
        .formStyle(.grouped)
        .probe("form")
    }

    /// The grouped style over a hidden scroll background.
    public static let groupedBackground = Fixture("form/grouped-background", size: CGSize(width: 360, height: 160)) {
        Form {
            Toggle("Enabled", isOn: .constant(true)).probe("toggle")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.yellow)
        .probe("form")
    }

    public static let all: [Fixture] = [basic, sections, styles, steps, grouped, groupedBackground]
}
