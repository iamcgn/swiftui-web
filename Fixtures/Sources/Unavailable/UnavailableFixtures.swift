// ContentUnavailableView fixtures: title with an image, a description, the search preset.
import SwiftUI
import FixtureKit

public enum UnavailableFixtures {
    public static let basic = Fixture("unavailable/basic", size: CGSize(width: 360, height: 400)) {
        VStack(spacing: 8) {
            ContentUnavailableView("No Mail", systemImage: "tray", description: Text("Try again later.")).probe("titled")
            ContentUnavailableView { Label("No Results", image: "icon").probe("customLabel") } description: { Text("Search again.").probe("description") } actions: { Button("Retry") {}.probe("action") }.probe("custom")
            ContentUnavailableView.search.probe("search")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
