// TabView fixtures: the macOS tab view (a segmented tab bar over a bordered content area), a
// selection binding switched in a step, tab items with images.
import SwiftUI
import FixtureKit

@Observable
public final class TabModel {
    public var selection = 0
    public init() {}
}

public enum TabViewFixtures {
    public static let basic = Fixture(
        "tabview/basic", size: CGSize(width: 360, height: 260),
        model: { TabModel() },
        steps: [FixtureStep("second") { $0.selection = 1 }]
    ) { model in
        TabView(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            // Only the selected tab's content is probed: hidden tabs are laid out somewhere
            // else by AppKit, which nothing here reproduces.
            Group { if model.selection == 0 { Text("First").probe("first") } else { Text("First") } }.tabItem { Text("One") }.tag(0)
            Group { if model.selection == 1 { Text("Second").probe("second") } else { Text("Second") } }.tabItem { Label("Two", image: "icon") }.tag(1)
            Color.red.frame(width: 60, height: 40).tabItem { Text("Three") }.tag(2)
        }
        .probe("tabs")
    }

    public static let sized = Fixture("tabview/sized", size: CGSize(width: 360, height: 260)) {
        TabView {
            Text("Alpha").probe("alpha").tabItem { Text("A") }
            Text("Beta").tabItem { Text("B") }
        }
        .frame(width: 240, height: 160)
        .probe("tabs")
    }

    /// The Tab API: three tabs with symbols (ignored by the macOS bar), one disabled, one with a
    /// badge; a step selects the second.
    public static let tabAPI = Fixture(
        "tabview/tab-api", size: CGSize(width: 360, height: 260),
        model: { TabModel() },
        steps: [FixtureStep("second") { $0.selection = 1 }]
    ) { model in
        TabView(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            Tab("Home", systemImage: "house", value: 0) {
                Group { if model.selection == 0 { Text("Home content").probe("home") } else { Text("Home content") } }
            }
            Tab("Alerts", systemImage: "bell", value: 1) {
                Group { if model.selection == 1 { Text("Alerts content").probe("alerts") } else { Text("Alerts content") } }
            }
            .badge(3)
            Tab("Off", systemImage: "gear", value: 2) {
                Text("Off content")
            }
            .disabled(true)
        }
        .probe("tabs")
    }

    // The page style is iOS-only in SwiftUI (`ios/tabs/page`).

    public static let all: [Fixture] = [basic, sized, tabAPI]
}
