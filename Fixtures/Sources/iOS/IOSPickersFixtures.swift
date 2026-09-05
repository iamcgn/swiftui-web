// The iOS looks of the menu button and a footer followed by a header. (The compact date picker is
// not measurable on Catalyst, which draws the Mac field: Docs/elements/iOS.md.)
import SwiftUI
import FixtureKit

public enum IOSPickersFixtures {
    /// Menu buttons: the automatic look, the button style, a hidden indicator, in a row with text.
    public static let menu = Fixture("ios/menu/basic", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            Menu("Options") { Button("Cut") {}; Button("Copy") {} }.probe("menu")
            Menu("Plain") { Button("Cut") {} }.menuStyle(.button).probe("buttonStyle")
            Menu("Hidden") { Button("Cut") {} }.menuIndicator(.hidden).probe("noIndicator")
            Menu("Off") { Button("Cut") {} }.disabled(true).probe("disabled")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hg").probe("rowText")
                Menu("Options") { Button("Cut") {} }.probe("rowMenu")
            }
            .probe("row")
        }
        .probe("stack")
    }.platform(.iOS)

    /// A footer followed by the next section's header.
    public static let listFooterHeader = Fixture("ios/list/footer-header", size: CGSize(width: 320, height: 400)) {
        List {
            Section {
                Text("Apple").probe("row1")
            } footer: {
                Text("Banana").probe("footer")
            }
            Section("Fruit") {
                Text("Cherry").probe("row2")
            }
        }
        .probe("list")
    }.platform(.iOS)

    public static let all: [Fixture] = [menu, listFooterHeader]
}
