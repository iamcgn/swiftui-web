// Menu fixture: pull-down menus with a title, a custom label, a primary action, the button style
// and a hidden indicator, plus a context menu. The golden holds the base state only (macOS opens
// menus in separate windows the hosted golden window cannot capture); Playwright/menu-probe.mjs
// drives them in the browser.
import SwiftUI
import FixtureKit

@Observable
public final class MenuModel {
    public var last = "none"
    public var primary = 0
    public init() {}
}

public enum MenuFixtures {
    public static let basic = Fixture(
        "menu/basic", size: CGSize(width: 360, height: 240),
        model: { MenuModel() },
        steps: []
    ) { model in
        VStack(spacing: 12) {
            Menu("Options") {
                Button("Cut") { model.last = "Cut" }
                Button("Copy") { model.last = "Copy" }
                Divider()
                Menu("More") { Button("Paste") { model.last = "Paste" } }
            }
            .probe("options")
            Menu { Button("Delete", role: .destructive) { model.last = "Delete" } } label: { Text("Custom") }
                .probe("custom")
            Menu("Primary") { Button("Cut") { model.last = "Cut" } } primaryAction: { model.primary += 1 }
                .probe("primary")
            Menu("Plain") { Button("Cut") { model.last = "Cut" } }.menuStyle(.button).probe("buttonStyle")
            Menu("Hidden") { Button("Cut") { model.last = "Cut" } }.menuIndicator(.hidden).probe("noIndicator")
            Text("Right-click me").contextMenu { Button("Action") { model.last = "Action" } }.probe("context")
            Text("Last: \(model.last) \(model.primary)").probe("last")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
