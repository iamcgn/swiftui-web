// List looks (`ios/list/spacing`, `list/alternating`, `list/prominence`, `list/outline`, `list/tint`,
// `list/separators`, `list/background`, `list/pinning`): row and section spacing, alternating
// row fills, header prominence, outline lists and disclosure groups in a list, item tints, the
// section separator modifiers, a hidden scroll content background, and the pinned header as the
// list scrolls (Docs/elements/List.md).
import SwiftUI
import FixtureKit

public struct OutlineNode: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let children: [OutlineNode]?
    public init(_ name: String, children: [OutlineNode]? = nil) { id = name; self.name = name; self.children = children }
    public static let tree = [
        OutlineNode("Fruits", children: [OutlineNode("Apple"), OutlineNode("Banana")]),
        OutlineNode("Vegetables", children: [OutlineNode("Carrot")]),
        OutlineNode("Water"),
    ]
}

@Observable
public final class ListScrollModel {
    public var proxy: ScrollViewProxy?
    public init() {}
}

public enum ListLooksFixtures {
    /// `listRowSpacing` and `listSectionSpacing` are iOS API: measured on the simulator.
    public static let spacing = Fixture("ios/list/spacing", size: CGSize(width: 320, height: 400)) {
        List {
            Section("First") {
                Text("Apple").probe("a1")
                Text("Banana").probe("a2")
            }
            Section("Second") {
                Text("Cherry").probe("b1")
                Text("Carrot").probe("b2")
            }
        }
        .fixtureListSpacing(row: 12, section: 30)
        .probe("list")
    }.platform(.iOS)

    public static let alternating = Fixture("list/alternating", size: CGSize(width: 320, height: 300)) {
        VStack(spacing: 8) {
            #if !os(iOS)   // macOS-only API (true on macOS, wasm and Linux); the iOS builds render only ios/ fixtures
            List {
                Text("Apple").probe("altRow1"); Text("Banana").probe("altRow2"); Text("Cherry").probe("altRow3"); Text("Carrot").probe("altRow4")
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(height: 130)
            .probe("insetAlternating")
            List {
                Text("Apple").probe("enabledRow1"); Text("Banana").probe("enabledRow2"); Text("Cherry").probe("enabledRow3")
            }
            .alternatingRowBackgrounds(.enabled)
            .frame(height: 130)
            .probe("enabled")
            #endif
        }
        .probe("stack")
    }

    public static let prominence = Fixture("list/prominence", size: CGSize(width: 320, height: 220)) {
        List {
            Section {
                Text("Apple").probe("row1")
            } header: {
                Text("Increased").probe("increasedHeader")
            }
            .headerProminence(.increased)
            Section {
                Text("Banana").probe("row2")
            } header: {
                Text("Standard").probe("standardHeader")
            }
        }
        .probe("list")
    }

    public static let outline = Fixture("list/outline", size: CGSize(width: 320, height: 300)) {
        VStack(spacing: 8) {
            List(OutlineNode.tree, children: \.children) { node in
                Text(node.name).probe(node.name)
            }
            .frame(height: 130)
            .probe("outline")
            List {
                DisclosureGroup("Fruits", isExpanded: .constant(true)) {
                    Text("Apple").probe("dgApple")
                    Text("Banana").probe("dgBanana")
                }
                .probe("dgFruits")
                Text("Water").probe("dgWater")
            }
            .frame(height: 130)
            .probe("disclosure")
        }
        .probe("stack")
    }

    public static let tint = Fixture("list/tint", size: CGSize(width: 320, height: 200)) {
        List {
            Label("Wi-Fi", systemImage: "wifi").listItemTint(.green).probe("green")
            Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right").listItemTint(ListItemTint.fixed(.orange)).probe("orange")
            Label("Mobile", systemImage: "phone").probe("plain")
        }
        .probe("list")
    }

    public static let separators = Fixture("list/separators", size: CGSize(width: 320, height: 300)) {
        List {
            Section("Hidden") {
                Text("Apple").probe("hiddenRow1")
                Text("Banana").probe("hiddenRow2")
            }
            .listSectionSeparator(.hidden)
            Section("Tinted") {
                Text("Cherry").probe("tintedRow1")
                Text("Carrot").probe("tintedRow2")
            }
            .listSectionSeparatorTint(Color.red)
            Section("Rows") {
                Text("Top").listRowSeparator(.hidden, edges: .top).probe("topHidden")
                Text("Bottom").listRowSeparator(.hidden, edges: .bottom).probe("bottomHidden")
                Text("Last").probe("last")
            }
        }
        .probe("list")
    }

    public static let background = Fixture("list/background", size: CGSize(width: 320, height: 200)) {
        List {
            Text("Apple").probe("row1")
            Text("Banana").probe("row2")
        }
        .scrollContentBackground(.hidden)
        .background(Color.yellow)
        .probe("list")
    }

    /// The pinned header follows the sections as the list scrolls (a step scrolls to a row of
    /// the second section).
    public static let pinning = Fixture(
        "list/pinning", size: CGSize(width: 320, height: 200),
        model: { ListScrollModel() },
        steps: [FixtureStep("scroll") { $0.proxy?.scrollTo("b3", anchor: .top) }]
    ) { model in
        ScrollViewReader { proxy in
            List {
                Section("First") {
                    ForEach(1...6, id: \.self) { index in Text("Row \(index)").id("a\(index)").probe("a\(index)") }
                }
                Section("Second") {
                    ForEach(1...6, id: \.self) { index in Text("Item \(index)").id("b\(index)").probe("b\(index)") }
                }
            }
            .onAppear { model.proxy = proxy }
        }
        .probe("list")
    }

    public static let all: [Fixture] = [spacing, alternating, prominence, outline, tint, separators, background, pinning]
}
