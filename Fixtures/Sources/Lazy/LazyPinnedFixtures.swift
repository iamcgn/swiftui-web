// Laziness, pinned section headers and footers, sections and cell alignment in lazy grids
// (Docs/elements/Lazy.md, "Laziness and pinning").
import SwiftUI
import FixtureKit

/// Drives the scrolling steps: a reader target.
@Observable
public final class LazyScrollModel {
    public var target: String? = nil
    public var anchor: UnitPoint? = .top
    public init() {}
}

/// A section of `count` 20 pt rows between a 24 pt header and a 16 pt footer, probed
/// `<prefix>H`, `<prefix>0…`, `<prefix>F`; rows carry ids `<prefix><i>`.
struct PinnedSection: View {
    let prefix: String
    var count = 8
    var body: some View {
        Section {
            ForEach(0..<count, id: \.self) { index in
                (index.isMultiple(of: 2) ? Color.blue : Color.orange)
                    .frame(width: 200, height: 20)
                    .probe("\(prefix)\(index)")
                    .id("\(prefix)\(index)")
            }
        } header: {
            Color.gray.frame(width: 200, height: 24).probe("\(prefix)H")
        } footer: {
            Color.black.frame(width: 200, height: 16).probe("\(prefix)F")
        }
    }
}

struct PinnedStack: View {
    let model: LazyScrollModel
    var pinned: PinnedScrollableViews
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: pinned) {
                    PinnedSection(prefix: "a")
                    PinnedSection(prefix: "b")
                    PinnedSection(prefix: "c")
                }
            }
            .probe("scroll")
            .onChange(of: model.target) { _, target in
                if let target { proxy.scrollTo(target, anchor: model.anchor) }
            }
        }
    }
}

struct LazyRows: View {
    let model: LazyScrollModel
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<200, id: \.self) { index in
                        (index.isMultiple(of: 2) ? Color.blue : Color.orange)
                            .frame(width: 200, height: 20)
                            .probe("r\(index)")
                            .id("r\(index)")
                    }
                }
            }
            .probe("scroll")
            .onChange(of: model.target) { _, target in
                if let target { proxy.scrollTo(target, anchor: model.anchor) }
            }
        }
    }
}

public enum LazyPinnedFixtures {
    /// Pinned section headers: the current section's header sticks to the top and the next
    /// pushes it away (steps scroll row b3 to the top, then the second header's row bH under the
    /// centre).
    public static let pinnedHeaders = Fixture(
        "lazy/pinned-headers", size: CGSize(width: 300, height: 200),
        model: { LazyScrollModel() },
        steps: [
            FixtureStep("b3") { $0.target = "b3" },
            FixtureStep("a7") { $0.anchor = .bottom; $0.target = "a7" },   // the second header just below
        ]
    ) { model in
        PinnedStack(model: model, pinned: .sectionHeaders)
    }

    /// Pinned section footers.
    public static let pinnedFooters = Fixture(
        "lazy/pinned-footers", size: CGSize(width: 300, height: 200),
        model: { LazyScrollModel() },
        steps: [
            FixtureStep("b3") { $0.target = "b3" },
            FixtureStep("b0-bottom") { $0.anchor = .bottom; $0.target = "b0" },
        ]
    ) { model in
        PinnedStack(model: model, pinned: .sectionFooters)
    }

    /// Both pinned at once.
    public static let pinnedBoth = Fixture(
        "lazy/pinned-both", size: CGSize(width: 300, height: 200),
        model: { LazyScrollModel() },
        steps: [FixtureStep("b3") { $0.target = "b3" }]
    ) { model in
        PinnedStack(model: model, pinned: [.sectionHeaders, .sectionFooters])
    }

    /// 200 rows: which rows exist (probes report only created rows), at rest and scrolled.
    public static let laziness = Fixture(
        "lazy/laziness", size: CGSize(width: 300, height: 200),
        model: { LazyScrollModel() },
        steps: [FixtureStep("r100") { $0.target = "r100" }]
    ) { model in
        LazyRows(model: model)
    }

    /// Sections in a lazy grid: headers and footers take a line of their own. The ids are unique
    /// across the sections: a lazy container drops cells whose id another cell already has.
    public static let gridSections = Fixture("lazy/grid-sections", size: CGSize(width: 300, height: 300)) {
        ScrollView {
            LazyVGrid(columns: [GridItem(.fixed(60)), GridItem(.fixed(60)), GridItem(.fixed(60))], spacing: 4) {
                Section {
                    ForEach(0..<5, id: \.self) { index in Color.red.frame(height: 20).probe("a\(index)") }
                } header: {
                    Color.gray.frame(height: 24).probe("aH")
                } footer: {
                    Color.black.frame(height: 16).probe("aF")
                }
                Section {
                    ForEach(10..<14, id: \.self) { index in Color.blue.frame(height: 20).probe("b\(index - 10)") }
                } header: {
                    Text("Second").probe("bH")
                }
            }
            .probe("grid")
        }
        .frame(width: 240)
        .probe("scroll")
    }

    /// `GridItem.alignment` against the grid's: tracks of 60 with a leading, a default and a
    /// bottom-trailing item in a `.trailing` grid; one tall cell makes the line 40.
    public static let gridAlignment = Fixture("lazy/grid-alignment", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.fixed(60), alignment: .leading), GridItem(.fixed(60)), GridItem(.fixed(60), alignment: .bottomTrailing)],
                      alignment: .trailing, spacing: 4) {
                Color.red.frame(width: 20, height: 20).probe("t0")
                Color.red.frame(width: 20, height: 40).probe("t1")
                Color.red.frame(width: 20, height: 20).probe("t2")
                Color.blue.frame(width: 20, height: 20).probe("t3")
            }
            .frame(width: 240)
            .probe("trailing")
            LazyVGrid(columns: [GridItem(.fixed(60), alignment: .leading), GridItem(.fixed(60)), GridItem(.fixed(60), alignment: .bottomTrailing)],
                      alignment: .leading, spacing: 4) {
                Color.red.frame(width: 20, height: 20).probe("l0")
                Color.red.frame(width: 20, height: 40).probe("l1")
                Color.red.frame(width: 20, height: 20).probe("l2")
            }
            .frame(width: 240)
            .probe("leading")
        }
    }

    public static let all: [Fixture] = [pinnedHeaders, pinnedFooters, pinnedBoth, laziness, gridSections, gridAlignment]
}
