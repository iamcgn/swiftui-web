// List fixtures: the macOS inset list (default) with plain rows, taller rows, rows with
// controls, sections with headers and footers, list styles, row modifiers, data-driven lists
// and a behaviour fixture that changes the selection.
import SwiftUI
import FixtureKit

public struct ListItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
    public static let fruits = [ListItem(id: 1, name: "Apple"), ListItem(id: 2, name: "Banana"), ListItem(id: 3, name: "Cherry")]
}

/// Drives `list/steps`.
@Observable
public final class ListSelectionModel {
    public var selection: Int? = nil
    public var items = ListItem.fruits
    public init() {}
}

public enum ListFixtures {
    /// Row geometry: text rows, a tall row, a full-width row, a label and a toggle row.
    public static let basic = Fixture("list/basic", size: CGSize(width: 320, height: 260)) {
        List {
            Text("Apple").probe("row1")
            Text("Banana").probe("row2")
            Color.red.frame(height: 40).probe("tall")
            HStack { Text("Cherry").probe("wideText"); Spacer(); Text("A").probe("wideTrailing") }.probe("wide")
            Label("Title", image: "icon").probe("label")
            Toggle("Enabled", isOn: .constant(true)).probe("toggle")
        }
        .probe("list")
    }

    /// Sections with headers and footers, and the sectioned data forms.
    public static let sections = Fixture("list/sections", size: CGSize(width: 320, height: 300)) {
        List {
            Section("Fruits") {
                Text("Apple").probe("apple")
                Text("Banana").probe("banana")
            }
            .probe("fruits")
            Section {
                Text("Carrot").probe("carrot")
            } header: {
                Text("Vegetables").probe("vegHeader")
            } footer: {
                Text("Footer").probe("vegFooter")
            }
            .probe("vegetables")
            Section {
                Text("Cherry").probe("cherry")
            }
            .probe("plainSection")
        }
        .probe("list")
    }

    /// The list styles, each in its own 70 pt tall frame.
    public static let styles = Fixture("list/styles", size: CGSize(width: 320, height: 320)) {
        VStack(spacing: 8) {
            List { Text("Apple").probe("insetRow1"); Text("Banana").probe("insetRow2") }.listStyle(.inset).frame(height: 70).probe("inset")
            List { Text("Apple").probe("plainRow1"); Text("Banana").probe("plainRow2") }.listStyle(.plain).frame(height: 70).probe("plain")
            List { Text("Apple").probe("borderedRow1"); Text("Banana").probe("borderedRow2") }.listStyle(.bordered).frame(height: 70).probe("bordered")
            List { Text("Apple").probe("sidebarRow1"); Text("Banana").probe("sidebarRow2") }.listStyle(.sidebar).frame(height: 70).probe("sidebar")
        }
        .probe("stack")
    }

    /// Row modifiers: insets, background, hidden separator; a data-driven list.
    public static let modifiers = Fixture("list/modifiers", size: CGSize(width: 320, height: 260)) {
        List {
            Text("Apple").listRowInsets(EdgeInsets(top: 2, leading: 30, bottom: 2, trailing: 10)).probe("inset")
            Text("Banana").listRowBackground(Color.yellow).probe("background")
            Text("Cherry").listRowSeparator(.hidden).probe("noSeparator")
            Text("Carrot").listRowSeparatorTint(Color.red).probe("tinted")
            ForEach(ListItem.fruits) { item in Text(item.name).probe("item\(item.id)") }
        }
        .probe("list")
    }

    /// Behaviour: selection follows the model; items can be removed.
    public static let steps = Fixture(
        "list/steps", size: CGSize(width: 320, height: 200),
        model: { ListSelectionModel() },
        steps: [
            FixtureStep("select") { $0.selection = 2 },
            FixtureStep("remove") { $0.items.removeFirst() },
            FixtureStep("deselect") { $0.selection = nil },
        ]
    ) { model in
        List(model.items, selection: Binding(get: { model.selection }, set: { model.selection = $0 })) { item in
            Text(item.name).probe("item\(item.id)")
        }
        .probe("list")
    }

    public static let all: [Fixture] = [basic, sections, styles, modifiers, steps]
}
