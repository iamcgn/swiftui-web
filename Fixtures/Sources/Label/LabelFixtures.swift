// Label fixtures: icon and title from a catalog image, the label styles, custom title and icon
// views, a tall icon, baseline alignment, and a label inside a bordered button.
import SwiftUI
import FixtureKit

public enum LabelFixtures {
    public static let basic = Fixture("label/basic", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            Label("Title", image: "icon").probe("label")
            Label("Title", image: "icon").labelStyle(.titleOnly).probe("titleOnly")
            Label("Title", image: "icon").labelStyle(.iconOnly).probe("iconOnly")
            Label("Title", image: "icon").labelStyle(.titleAndIcon).probe("titleAndIcon")
            Label(title: { Text("Title").probe("customTitle") },
                  icon: { Circle().fill(Color.red).frame(width: 12, height: 12).probe("customIcon") }).probe("custom")
            Label(title: { Text("Hg").probe("tallTitle") }, icon: { Image("swatch").probe("tallIcon") }).probe("tall")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Hg", image: "icon").probe("rowLabel")
                Text("Hg").probe("rowText")
            }
            .probe("row")
            Button(action: {}) { Label("Title", image: "icon").probe("buttonLabel") }.probe("button")
        }
        .probe("stack")
    }

    /// Corners (sw-label-forms): a two-line title (the icon aligns with the first line), a
    /// text-only icon, a label in a menu's label, and labelled content with formatted values and
    /// controls in a grouped form.
    public static let corners = Fixture("label/corners", size: CGSize(width: 360, height: 320)) {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text("A title that wraps onto a second line here").probe("wrappedTitle") } icon: { Image(systemName: "star").probe("wrappedIcon") }
                .frame(width: 180).probe("wrapped")
            Label { Text("Arrow").probe("textIconTitle") } icon: { Text("→").probe("textIcon") }.probe("textIconLabel")
            Form {
                LabeledContent("Price", value: 12.5, format: .number).probe("number")
                LabeledContent("Share", value: 0.25, format: .percent).probe("percent")
                LabeledContent("Enabled") { Toggle("", isOn: .constant(true)).labelsHidden().probe("toggleContent") }.probe("toggle")
                LabeledContent("Kind") { Picker("", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.labelsHidden().probe("pickerContent") }.probe("picker")
                LabeledContent("Plain", value: "Value").probe("plain")
            }
            .formStyle(.grouped)
            .frame(height: 190)
            .probe("form")
        }
        .padding(.top, 10)
    }

    public static let all: [Fixture] = [basic, corners]
}
