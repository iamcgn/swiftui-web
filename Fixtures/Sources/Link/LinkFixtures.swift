// Link fixtures: a titled link, a link with a custom label, links in a stack next to text
// (colour and spacing) and a disabled link.
import SwiftUI
import FixtureKit

public enum LinkFixtures {
    public static let basic = Fixture("link/basic", size: CGSize(width: 320, height: 200)) {
        VStack(spacing: 12) {
            Link("Apple", destination: URL(string: "https://www.apple.com")!).probe("titled")
            Link(destination: URL(string: "https://www.apple.com")!) { Label("Open site", image: "icon").probe("customLabel") }.probe("custom")
            HStack(spacing: 8) {
                Text("Visit").probe("text")
                Link("the site", destination: URL(string: "https://www.apple.com")!).probe("inline")
            }
            .probe("row")
            Link("Disabled", destination: URL(string: "https://www.apple.com")!).disabled(true).probe("disabled")
            Link("Large", destination: URL(string: "https://www.apple.com")!).font(.title).probe("large")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
