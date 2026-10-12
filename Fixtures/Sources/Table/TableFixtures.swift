// Table fixtures: the macOS table (column headers, rows, alternating backgrounds), key-path
// and custom columns, column widths, a frame, a selection binding driven by steps, and a sort
// order binding driven by steps.
import SwiftUI
import FixtureKit

public struct TableFruit: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let color: String
    public let count: Int
    public init(id: Int, name: String, color: String, count: Int) {
        self.id = id; self.name = name; self.color = color; self.count = count
    }
}

/// Drives `table/selection`.
@Observable
public final class TableSelectionModel {
    public var selection: Int? = nil
    public init() {}
}

/// Drives `table/sorting`.
@Observable
public final class TableSortModel {
    public var order = [KeyPathComparator(\TableFruit.name)]
    public init() {}
}

public enum TableFixtures {
    public static let fruits = [
        TableFruit(id: 1, name: "Apple", color: "Red", count: 3),
        TableFruit(id: 2, name: "Banana", color: "Yellow", count: 12),
        TableFruit(id: 3, name: "Cherry", color: "Red", count: 40),
    ]

    public static let basic = Fixture("table/basic", size: CGSize(width: 360, height: 220)) {
        Table(fruits) {
            TableColumn("Name", value: \.name)
            TableColumn("Color") { fruit in Text(fruit.color).probe("color\(fruit.id)") }
            TableColumn("Count") { fruit in Text("\(fruit.count)").probe("count\(fruit.id)") }
        }
        .probe("table")
    }

    public static let widths = Fixture("table/widths", size: CGSize(width: 360, height: 220)) {
        Table(fruits) {
            TableColumn("Name") { fruit in Text(fruit.name).probe("name\(fruit.id)") }.width(80)
            TableColumn("Color") { fruit in Text(fruit.color).probe("color\(fruit.id)") }.width(min: 40, ideal: 60, max: 100)
            TableColumn("Count") { fruit in Text("\(fruit.count)").probe("count\(fruit.id)") }
        }
        .probe("table")
    }

    public static let sized = Fixture("table/sized", size: CGSize(width: 360, height: 220)) {
        VStack(spacing: 8) {
            Text("Above").probe("above")
            Table(fruits) {
                TableColumn("Name") { fruit in Text(fruit.name).probe("name\(fruit.id)") }
                TableColumn("Color", value: \.color)
            }
            .frame(width: 240, height: 120)
            .probe("table")
        }
        .probe("stack")
    }

    public static let selection = Fixture(
        "table/selection", size: CGSize(width: 360, height: 220),
        model: { TableSelectionModel() },
        steps: [
            FixtureStep("select1") { $0.selection = 1 },
            FixtureStep("select3") { $0.selection = 3 },
            FixtureStep("clear") { $0.selection = nil },
        ]
    ) { model in
        Table(fruits, selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            TableColumn("Name") { fruit in Text(fruit.name).probe("name\(fruit.id)") }
            TableColumn("Color", value: \.color)
        }
        .probe("table")
    }

    public static let sorting = Fixture(
        "table/sorting", size: CGSize(width: 360, height: 220),
        model: { TableSortModel() },
        steps: [
            FixtureStep("byCount") { $0.order = [KeyPathComparator(\TableFruit.count, order: .reverse)] },
        ]
    ) { model in
        Table(fruits.sorted(using: model.order), sortOrder: Binding(get: { model.order }, set: { model.order = $0 })) {
            TableColumn("Name", value: \.name) { fruit in Text(fruit.name).probe("name\(fruit.id)") }
            TableColumn("Count", value: \.count) { fruit in Text("\(fruit.count)").probe("count\(fruit.id)") }
        }
        .probe("table")
    }

    /// The other two width regimes: two automatic columns that do not fit 200 pt keep their
    /// 117 pt pitch and overflow; four columns in 600 pt grow into it by half points.
    public static let regimes = Fixture("table/regimes", size: CGSize(width: 600, height: 300)) {
        VStack(spacing: 8) {
            Table(fruits) {
                TableColumn("Name") { fruit in Text(fruit.name).probe("oname\(fruit.id)") }
                TableColumn("Color") { fruit in Text(fruit.color).probe("ocolor\(fruit.id)") }
            }
            .frame(width: 200, height: 120)
            .probe("overflow")
            Table(fruits) {
                TableColumn("Name") { fruit in Text(fruit.name).probe("gname\(fruit.id)") }
                TableColumn("Color") { fruit in Text(fruit.color).probe("gcolor\(fruit.id)") }
                TableColumn("Count") { fruit in Text("\(fruit.count)").probe("gcount\(fruit.id)") }
                TableColumn("Empty") { fruit in Text("Empty").probe("gempty\(fruit.id)") }
            }
            .probe("grow")
        }
        .probe("stack")
    }

    /// A tree for the outline table (`Table(_:children:columns:)`).
    public struct Node: Identifiable, Sendable {
        public let id: Int
        public let name: String
        public let children: [Node]?
        public init(id: Int, name: String, children: [Node]? = nil) { self.id = id; self.name = name; self.children = children }
    }

    public static let tree = [
        Node(id: 1, name: "Fruit", children: [Node(id: 11, name: "Apple"), Node(id: 12, name: "Banana")]),
        Node(id: 2, name: "Cherry"),
    ]

    /// Corners (sw-table, macOS 27): hidden headers, no alternating bands, the bordered style,
    /// `TableRow` builders and a group of columns, all in one window.
    public static let corners = Fixture("table/corners", size: CGSize(width: 360, height: 360)) {
        VStack(spacing: 8) {
            Table(fruits) {
                TableColumn("Name") { Text($0.name).probe("hiddenName\($0.id)") }
                TableColumn("Count") { Text("\($0.count)") }
            }
            .tableColumnHeaders(.hidden)
            .probe("hidden")
            #if !os(iOS)   // macOS-only API (true on macOS, wasm and Linux); the iOS builds render only ios/ fixtures
            Table(fruits) {
                TableColumn("Name", value: \.name)
                Group {
                    TableColumn("Color", value: \TableFruit.color)
                    TableColumn("Count") { (fruit: TableFruit) in Text("\(fruit.count)").probe("count\(fruit.id)") }
                }
            }
            .alternatingRowBackgrounds(.disabled)
            .tableStyle(.bordered)
            .probe("bordered")
            #endif
            Table(of: TableFruit.self) {
                TableColumn("Name") { Text($0.name).probe("rowName\($0.id)") }
                TableColumn("Color", value: \.color)
            } rows: {
                TableRow(fruits[0])
                TableRow(fruits[2])
            }
            .probe("rows")
        }
    }

    /// Outline rows: a tree with disclosure triangles, the first group expanded by a step.
    public static let outline = Fixture("table/outline", size: CGSize(width: 360, height: 160)) {
        Table(tree, children: \.children) {
            TableColumn("Name", value: \.name)
            TableColumn("ID") { Text("\($0.id)").probe("id\($0.id)") }
        }
        .probe("outline")
    }

    public static let all: [Fixture] = [basic, widths, sized, selection, sorting, regimes, corners, outline]
}
