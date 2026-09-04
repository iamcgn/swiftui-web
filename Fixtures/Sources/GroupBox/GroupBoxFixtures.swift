// GroupBox fixtures: a titled box, an untitled box, a custom label, a box stretched by its
// content, and nested boxes.
import SwiftUI
import FixtureKit

public enum GroupBoxFixtures {
    public static let basic = Fixture("groupbox/basic", size: CGSize(width: 320, height: 400)) {
        VStack(spacing: 12) {
            GroupBox("Settings") {
                VStack(alignment: .leading) {
                    Text("Inside").probe("inside")
                    Toggle("Option", isOn: .constant(true)).probe("toggle")
                }
                .probe("content")
            }
            .probe("titled")
            GroupBox { Text("Plain content").probe("plainContent") }.probe("plain")
            GroupBox { Text("Custom") } label: { Label("Custom", image: "icon").probe("customLabel") }.probe("custom")
            GroupBox("Wide") { Text("Wide").frame(maxWidth: .infinity).probe("wideContent") }.probe("wide")
            GroupBox("Outer") {
                GroupBox("Inner") { Text("Nested").probe("nested") }.probe("inner")
            }
            .probe("outer")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
