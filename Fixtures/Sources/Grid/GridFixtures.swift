// Grid fixtures: rows of cells, spacing, cell modifiers (column span, column alignment, anchor,
// unsized axes), grid alignment, flexible cells and a non-row child spanning the columns.
import SwiftUI
import FixtureKit

public enum GridFixtures {
    /// Cells of different widths and heights: columns as wide as their widest cell, rows as tall as their tallest.
    public static let basic = Fixture("grid/basic", size: CGSize(width: 320, height: 200)) {
        Grid {
            GridRow {
                Text("A").probe("a")
                Text("BB").probe("bb")
                Text("CCC").probe("ccc")
            }
            .probe("row1")
            GridRow {
                Color.red.frame(width: 30, height: 20).probe("red")
                Text("E").probe("e")
                Color.blue.frame(width: 50, height: 40).probe("blue")
            }
            GridRow {
                Text("G").probe("g")
                Text("H").probe("h")
            }
        }
        .probe("grid")
    }

    /// Explicit spacings and a top-leading alignment.
    public static let spacing = Fixture("grid/spacing", size: CGSize(width: 320, height: 200)) {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 4) {
            GridRow {
                Text("A").probe("a")
                Color.red.frame(width: 30, height: 30).probe("red")
            }
            GridRow {
                Color.blue.frame(width: 60, height: 20).probe("blue")
                Text("H").probe("h")
            }
        }
        .probe("grid")
    }

    /// Cell modifiers: a two-column span, per-column alignment, an anchor, unsized axes, and a
    /// non-row child spanning every column.
    public static let modifiers = Fixture("grid/modifiers", size: CGSize(width: 320, height: 240)) {
        Grid(alignment: .leading) {
            GridRow {
                Text("Header").gridCellColumns(2).probe("header")
                Text("CCC").probe("ccc")
            }
            GridRow {
                Text("A").gridColumnAlignment(.trailing).probe("a")
                Color.red.frame(width: 60, height: 40).probe("red")
                Text("E").gridCellAnchor(.bottomTrailing).probe("e")
            }
            Color.green.frame(height: 4).probe("divider")
            GridRow {
                Color.blue.gridCellUnsizedAxes(.horizontal).frame(height: 20).probe("blue")
                Text("H").probe("h")
            }
        }
        .probe("grid")
    }

    /// Grid alignment across rows and columns.
    public static let alignment = Fixture("grid/alignment", size: CGSize(width: 320, height: 200)) {
        HStack(alignment: .top, spacing: 16) {
            Grid(alignment: .bottomTrailing) {
                GridRow {
                    Text("A").probe("a")
                    Color.red.frame(width: 40, height: 40).probe("red")
                }
                GridRow {
                    Color.blue.frame(width: 60, height: 20).probe("blue")
                    Text("H").probe("h")
                }
            }
            .probe("bottomTrailing")
            Grid(alignment: .center) {
                GridRow {
                    Text("A").probe("ca")
                    Color.red.frame(width: 40, height: 40).probe("cred")
                }
                GridRow {
                    Color.blue.frame(width: 60, height: 20).probe("cblue")
                    Text("H").probe("ch")
                }
            }
            .probe("center")
        }
        .probe("row")
    }

    /// Flexible cells share the space a frame gives the grid.
    public static let flexible = Fixture("grid/flexible", size: CGSize(width: 320, height: 200)) {
        Grid {
            GridRow {
                Text("A").probe("a")
                Color.red.frame(height: 20).probe("red")
                Text("CCC").probe("ccc")
            }
            GridRow {
                Color.blue.frame(height: 30).probe("blue")
                Text("E").probe("e")
                Color.green.frame(height: 30).probe("green")
            }
        }
        .frame(width: 280)
        .probe("grid")
    }

    public static let all: [Fixture] = [basic, spacing, modifiers, alignment, flexible]
}
