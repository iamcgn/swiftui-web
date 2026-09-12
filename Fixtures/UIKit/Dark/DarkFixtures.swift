// Dark appearance (Docs/elements/UIKit/Dark.md): light fixtures rendered again with the window's
// interface style dark, so the system colours' dark values, the bars' and cards' dark looks and
// the controls' dark tints are measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum DarkFixtures {
    public static let all = [table, plainTable, controls, navigation, alert, list]

    public static let table = TableFixtures.grouped.renamed("uikit/dark/table").style(.dark)
    public static let plainTable = TableFixtures.plain.renamed("uikit/dark/plaintable").style(.dark)
    public static let controls = MoreControlFixtures.controls.renamed("uikit/dark/controls").style(.dark)
    public static let navigation = NavigationFixtures.basic.renamed("uikit/dark/nav").style(.dark)
    public static let alert = PresentationFixtures.alert.renamed("uikit/dark/alert").style(.dark)
    public static let list = CollectionFixtures.list.renamed("uikit/dark/list").style(.dark)
}
#endif
