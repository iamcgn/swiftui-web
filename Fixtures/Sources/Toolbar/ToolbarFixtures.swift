// Toolbars: the items live in the window chrome on macOS (outside the harness capture), so the
// golden shows the content alone; hosts that paint chrome draw the bar above the content
// (Playwright/toolbar-probe.mjs).
import SwiftUI
import FixtureKit

struct ToolbarDemo: View {
    @State private var taps = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Taps: \(taps)").probe("taps")
                Text("Content below the toolbar").probe("content")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Toolbar")
            .toolbar {
                ToolbarItem(placement: .navigation) { Button("Back") { taps += 10 } }
                ToolbarItem(placement: .primaryAction) { Button("Action") { taps += 1 } }
                ToolbarItemGroup { Button("One") { taps += 100 }; Button("Two") { taps += 1000 } }
            }
        }
        .probe("stack")
    }
}

/// `searchable`: the field is toolbar chrome; the list filters on the query.
struct SearchableDemo: View {
    @State private var query = ""
    static let fruit = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]
    var shown: [String] { query.isEmpty ? Self.fruit : Self.fruit.filter { $0.lowercased().contains(query.lowercased()) } }

    var body: some View {
        NavigationStack {
            List(shown, id: \.self) { name in Text(name).probe(name) }
                .navigationTitle("Fruit")
                .searchable(text: $query, prompt: "Find fruit")
        }
        .probe("stack")
    }
}

public enum ToolbarFixtures {
    public static let basic = Fixture("toolbar/basic", size: CGSize(width: 400, height: 200), content: { ToolbarDemo() })
    public static let searchable = Fixture("toolbar/searchable", size: CGSize(width: 400, height: 200), content: { SearchableDemo() })
    public static let all: [Fixture] = [basic, searchable]
}
