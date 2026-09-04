// LabeledContent fixtures: label/value pairs in a stack and in a form (the label column), custom
// labels and content, hidden labels.
import SwiftUI
import FixtureKit

public enum LabeledContentFixtures {
    public static let basic = Fixture("labeledcontent/basic", size: CGSize(width: 320, height: 260)) {
        VStack(spacing: 12) {
            LabeledContent("Name", value: "Corey").probe("value")
            LabeledContent("Count") { Text("3").probe("countContent") }.probe("count")
            LabeledContent { Text("Custom").probe("customContent") } label: { Label("Network", image: "icon").probe("customLabel") }.probe("custom")
            LabeledContent("Hidden", value: "Shown").labelsHidden().probe("hidden")
            LabeledContent("Toggle") { Toggle("", isOn: .constant(true)).labelsHidden().probe("toggleContent") }.probe("toggle")
            LabeledContent { Text("Value").probe("narrowContent") } label: { Text("Narrow").probe("narrowLabel") }.frame(width: 160).probe("narrow")
            LabeledContent("Wide", value: "Value").frame(maxWidth: .infinity).probe("wide")
        }
        .padding(20)
        .probe("stack")
    }

    public static let form = Fixture("labeledcontent/form", size: CGSize(width: 360, height: 200)) {
        Form {
            LabeledContent("Name", value: "Corey").probe("value")
            LabeledContent("Count") { Text("3").probe("countContent") }.probe("count")
            TextField("Email", text: .constant("")).probe("field")
        }
        .probe("form")
    }

    public static let all: [Fixture] = [basic, form]
}
