// symbolEffect at rest: inactive and untriggered effects leave the symbol as it is.
import SwiftUI
import FixtureKit

public enum SymbolEffectFixtures {
    public static let basic = Fixture("symboleffect/basic", size: CGSize(width: 240, height: 80), content: {
        HStack(spacing: 24) {
            Image(systemName: "star").symbolEffect(.pulse, isActive: false).probe("pulse")
            Image(systemName: "star").symbolEffect(.bounce, value: 0).probe("bounce")
            Image(systemName: "star").font(.title).symbolEffect(.scale, isActive: false).probe("scale")
            Image(systemName: "star").symbolEffect(.variableColor.iterative, options: .repeating, isActive: false).probe("variable")
        }
        .probe("row")
    })

    public static let all: [Fixture] = [basic]
}
