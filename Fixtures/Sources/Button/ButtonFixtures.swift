import SwiftUI
import FixtureKit

public enum ButtonFixtures {
    public static let basic = Fixture("button/basic", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 12) {
            Button("OK") {}.probe("ok")
            Button("Increment") {}.probe("increment")
            Button(action: {}) { Text("Label").probe("labelText") }.probe("labelButton")
            HStack {
                Button("−") {}.probe("minus")
                Button("+") {}.probe("plus")
            }
            .probe("row")
        }
        .probe("stack")
    }

    public static let styles = Fixture("button/styles", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 12) {
            Button("Plain") {}.buttonStyle(.plain).probe("plain")
            Button("Bordered") {}.buttonStyle(.bordered).probe("bordered")
            Button("Borderless") {}.buttonStyle(.borderless).probe("borderless")
            Button("Prominent") {}.buttonStyle(.borderedProminent).probe("prominent")
            Button("Padded") {}.padding().probe("paddedOuter")
        }
    }

    public static let all: [Fixture] = [basic, styles]
}
