// ShareLink fixtures: the default "Share" button, a titled one and a custom label.
import SwiftUI
import FixtureKit

public enum ShareLinkFixtures {
    public static let basic = Fixture("sharelink/basic", size: CGSize(width: 320, height: 160)) {
        VStack(spacing: 12) {
            ShareLink(item: URL(string: "https://www.apple.com")!).probe("plain")
            ShareLink("Send", item: URL(string: "https://www.apple.com")!).probe("titled")
            ShareLink(item: URL(string: "https://www.apple.com")!) { Label("Custom", image: "icon").probe("customLabel") }.probe("custom")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
