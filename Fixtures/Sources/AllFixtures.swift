import SwiftUI
import FixtureKit

/// Every fixture the harness and the tests know about. Keep sorted by name.
public enum AllFixtures {
    @MainActor public static let all: [Fixture] = [
        TextFixtures.hello,
    ]
}
