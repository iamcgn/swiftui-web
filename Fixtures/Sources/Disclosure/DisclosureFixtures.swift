// DisclosureGroup fixtures: a collapsed group that expands in a step, an expanded group, a
// custom label, and nested groups.
import SwiftUI
import FixtureKit

@Observable
public final class DisclosureModel {
    public var expanded = false
    public init() {}
}

public enum DisclosureFixtures {
    public static let basic = Fixture(
        "disclosure/basic", size: CGSize(width: 320, height: 300),
        model: { DisclosureModel() },
        steps: [FixtureStep("expand") { $0.expanded = true }]
    ) { model in
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup("Details", isExpanded: Binding(get: { model.expanded }, set: { model.expanded = $0 })) {
                Text("Inside").probe("inside")
                Toggle("Option", isOn: .constant(true)).probe("toggle")
            }
            .probe("group")
            DisclosureGroup(isExpanded: .constant(true)) {
                Text("Shown").probe("shownContent")
            } label: {
                Label("Network", image: "icon").probe("customLabel")
            }
            .probe("expanded")
            DisclosureGroup("Outer", isExpanded: .constant(true)) {
                DisclosureGroup("Inner", isExpanded: .constant(true)) {
                    Text("Nested").probe("nested")
                }
                .probe("inner")
            }
            .probe("outer")
        }
        .padding(20)
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
