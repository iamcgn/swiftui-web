// Named colours from Fixtures/Assets.xcassets colour sets (float, hex and integer components;
// the light variant of a set that also has a dark one).
import SwiftUI
import FixtureKit

public enum ColorFixtures {
    public static let named = Fixture("color/named", size: CGSize(width: 340, height: 120)) {
        HStack(spacing: 8) {
            Color("Accent").frame(width: 60, height: 60).probe("accent")
            Color("Panel").frame(width: 60, height: 60).probe("panel")
            Color("Warm").frame(width: 60, height: 60).probe("warm")
            Rectangle().fill(Color("Accent")).frame(width: 60, height: 60).probe("shape")
            Text("Hg").foregroundStyle(Color("Accent")).probe("text")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [named]
}
