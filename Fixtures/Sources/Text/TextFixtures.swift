import SwiftUI
import FixtureKit

public enum TextFixtures {
    public static let hello = Fixture("text/hello", size: CGSize(width: 200, height: 100)) {
        Text("Hello").probe("hello")
    }
}
