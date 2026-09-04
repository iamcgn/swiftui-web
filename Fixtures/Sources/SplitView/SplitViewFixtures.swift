// NavigationSplitView fixtures: the macOS sidebar/detail split (default and explicit column
// widths, three columns, a split view in a frame), list selection driving the detail, and
// column visibility through a binding.
import SwiftUI
import FixtureKit

/// Drives `splitview/selection`.
@Observable
public final class SplitSelectionModel {
    public var selection: Int? = nil
    public init() {}
}

/// Drives `splitview/visibility`.
@Observable
public final class SplitVisibilityModel {
    public var visibility: NavigationSplitViewVisibility = .detailOnly
    public init() {}
}

public enum SplitViewFixtures {
    /// A sidebar list and a detail text with the default column widths.
    public static let basic = Fixture("splitview/basic", size: CGSize(width: 480, height: 300)) {
        NavigationSplitView {
            List {
                Text("Apple").probe("row1")
                Text("Banana").probe("row2")
            }
            .probe("sidebar")
        } detail: {
            Text("Detail").probe("detail")
        }
        .probe("split")
    }

    /// An explicit sidebar width, a non-list sidebar, and a stack in the detail.
    public static let widths = Fixture("splitview/widths", size: CGSize(width: 480, height: 300)) {
        NavigationSplitView {
            VStack(spacing: 8) {
                Text("Menu").probe("menu")
                Color.red.frame(width: 40, height: 20).probe("swatch")
            }
            .navigationSplitViewColumnWidth(150)
            .probe("sidebar")
        } detail: {
            VStack(spacing: 8) {
                Text("Wide").probe("wide")
                Color.blue.frame(width: 40, height: 20).probe("box")
            }
            .probe("detailStack")
        }
        .probe("split")
    }

    /// Three columns: the content column with a min/ideal/max width.
    public static let three = Fixture("splitview/three", size: CGSize(width: 640, height: 300)) {
        NavigationSplitView {
            List { Text("Apple").probe("row1") }.probe("sidebar")
        } content: {
            List { Text("Cherry").probe("contentRow") }
                .navigationSplitViewColumnWidth(min: 120, ideal: 160, max: 220)
                .probe("content")
        } detail: {
            Text("Detail").probe("detail")
        }
        .probe("split")
    }

    /// Three columns with the defaults: a min/ideal/max sidebar and an unmodified content column.
    public static let columns = Fixture("splitview/columns", size: CGSize(width: 640, height: 300)) {
        NavigationSplitView {
            List { Text("Apple").probe("row1") }
                .navigationSplitViewColumnWidth(min: 100, ideal: 120, max: 200)
                .probe("sidebar")
        } content: {
            List { Text("Cherry").probe("contentRow") }.probe("content")
        } detail: {
            Text("Detail").probe("detail")
        }
        .probe("split")
    }

    /// A split view fills the frame it is given.
    public static let sized = Fixture("splitview/sized", size: CGSize(width: 480, height: 300)) {
        NavigationSplitView {
            List { Text("Apple").probe("row1") }.probe("sidebar")
        } detail: {
            Text("Detail").probe("detail")
        }
        .frame(width: 320, height: 200)
        .probe("split")
    }

    /// Behaviour: a sidebar selection drives the detail column.
    public static let selection = Fixture(
        "splitview/selection", size: CGSize(width: 480, height: 300),
        model: { SplitSelectionModel() },
        steps: [
            FixtureStep("select1") { $0.selection = 1 },
            FixtureStep("select2") { $0.selection = 2 },
            FixtureStep("clear") { $0.selection = nil },
        ]
    ) { model in
        NavigationSplitView {
            List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                Text("Apple").tag(1).probe("row1")
                Text("Banana").tag(2).probe("row2")
            }
            .probe("sidebar")
        } detail: {
            if let selection = model.selection {
                Text("Number \(selection)").probe("number\(selection)")
            } else {
                Text("Select").probe("placeholder")
            }
        }
        .probe("split")
    }

    /// Behaviour: the column visibility binding hides and shows the sidebar.
    public static let visibility = Fixture(
        "splitview/visibility", size: CGSize(width: 480, height: 300),
        model: { SplitVisibilityModel() },
        steps: [
            FixtureStep("showAll") { $0.visibility = .all },
            FixtureStep("detailOnly") { $0.visibility = .detailOnly },
        ]
    ) { model in
        NavigationSplitView(columnVisibility: Binding(get: { model.visibility }, set: { model.visibility = $0 })) {
            List { Text("Apple").probe("row1") }.probe("sidebar")
        } detail: {
            Text("Detail").probe("detail")
        }
        .probe("split")
    }

    public static let all: [Fixture] = [basic, widths, three, columns, sized, selection, visibility]
}
