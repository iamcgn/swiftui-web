import SwiftUI
import FixtureKit

/// Every fixture the harness and the tests know about. Keep sorted by name.
public enum AllFixtures {
    public static let all: [Fixture] = LayoutFixtures.all + [
        TextFixtures.hello,
    ]
}
