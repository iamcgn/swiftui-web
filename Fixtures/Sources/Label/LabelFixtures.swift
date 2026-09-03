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

    public static let all: [Fixture] = [basic]
}
