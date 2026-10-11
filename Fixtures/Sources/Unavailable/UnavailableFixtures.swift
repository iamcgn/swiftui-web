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

    /// Corners (sw-content-unavailable): inside a list (the view fills the list's space) and
    /// inside a navigation stack with a title.
    public static let corners = Fixture("unavailable/corners", size: CGSize(width: 360, height: 600)) {
        VStack(spacing: 8) {
            List {
                ContentUnavailableView {
                    Label { Text("No Items").probe("listTitle") } icon: { Image(systemName: "tray").probe("listIcon") }.probe("listLabel")
                } description: {
                    Text("Add one.").probe("listDescription")
                }
                .probe("inList")
            }
            .frame(height: 190)
            .probe("list")
            NavigationStack {
                ContentUnavailableView {
                    Label { Text("Nothing Here").probe("navTitle") } icon: { Image(systemName: "tray").probe("navIcon") }.probe("navLabel")
                }
                .probe("inNav")
                .navigationTitle("Items")
            }
            .frame(height: 190)
            .probe("nav")
            ContentUnavailableView {
                Label { Text("No Mail").probe("plainTitle") } icon: { Image(systemName: "tray").probe("plainIcon") }.probe("plainLabel")
            } description: {
                Text("Try again later.").probe("plainDescription")
            } actions: {
                Button("Retry") {}.probe("plainAction")
            }
            .frame(height: 190)
            .probe("plain")
        }
    }

    public static let all: [Fixture] = [basic, corners]
}
