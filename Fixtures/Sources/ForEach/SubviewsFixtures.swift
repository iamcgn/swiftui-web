// The container APIs (sw-subviews, Docs/elements/ForEach.md): `Group(subviews:)` and
// `ForEach(subviews:)` iterate a view's structural children (tuple elements, `ForEach`
// elements, a conditional's branch, a modifier on the container applied to each child),
// `Group(sections:)` and `ForEach(sections:)` its sections with their headers and footers, and
// `ContainerValues` carry per-child values set with `containerValue(_:_:)` and `tag(_:)`.
import SwiftUI
import FixtureKit

extension ContainerValues {
    @Entry var fixtureHighlighted: Bool = false
}

public enum SubviewsFixtures {
    /// Every subview in a yellow box, the first on its own line.
    public static let subviews = Fixture("foreach/subviews", size: CGSize(width: 320, height: 200)) {
        Group(subviews: SubviewsContent()) { subviews in
            VStack(alignment: .leading, spacing: 8) {
                subviews[0].padding(4).background(Color.yellow).probe("first")
                HStack(spacing: 8) {
                    ForEach(subviews.dropFirst()) { subview in
                        subview.padding(4).background(Color.yellow)
                    }
                }
                .probe("rest")
                Color.blue.frame(width: CGFloat(subviews.count) * 20, height: 10).probe("count")
            }
        }
        .probe("group")
    }

    /// `ForEach(subviews:)` in reverse, each child under a red bar.
    public static let forEach = Fixture("foreach/subviews-foreach", size: CGSize(width: 380, height: 160)) {
        HStack(alignment: .top, spacing: 10) {
            ForEach(subviews: SubviewsContent()) { subview in
                VStack(spacing: 2) {
                    Color.red.frame(height: 4)
                    subview
                }
            }
        }
        .probe("row")
    }

    /// Sections: each header above its rows, the footer under them, loose rows in a section of
    /// their own.
    public static let sections = Fixture("foreach/sections", size: CGSize(width: 320, height: 260)) {
        Group(sections: SectionsContent()) { sections in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        section.header
                        HStack(spacing: 6) { section.content }
                        section.footer
                    }
                    .padding(4)
                    .background(Color.yellow)
                }
                Color.blue.frame(width: CGFloat(sections.count) * 20, height: 10).probe("count")
            }
        }
        .probe("group")
    }

    /// Container values and tags read by the container: highlighted children get a green ground,
    /// tagged children a blue bar whose width is the tag.
    public static let values = Fixture("foreach/container-values", size: CGSize(width: 320, height: 160)) {
        Group(subviews: ValuesContent()) { subviews in
            HStack(spacing: 8) {
                ForEach(subviews) { subview in
                    VStack(spacing: 2) {
                        subview.padding(4).background(subview.containerValues.fixtureHighlighted ? Color.green : Color.clear)
                        Color.blue.frame(width: CGFloat(subview.containerValues.tag(for: Int.self) ?? 0), height: 4)
                    }
                }
            }
        }
        .probe("group")
    }

    public static let all: [Fixture] = [subviews, forEach, sections, values]
}

/// Children of several kinds: tuple elements, a `ForEach`, a conditional's branch, a `Group`
/// with a modifier (applied to each of its two children).
struct SubviewsContent: View {
    var body: some View {
        Text("Apple").probe("apple")
        ForEach(["Banana", "Cherry"], id: \.self) { Text($0).probe($0.lowercased()) }
        if true { Text("Alpha").probe("alpha") }
        Group {
            Text("Beta").probe("beta")
            Text("Gamma").probe("gamma")
        }
        .padding(.leading, 6)
    }
}

/// Two sections and loose rows.
struct SectionsContent: View {
    var body: some View {
        Section {
            Text("Apple").probe("apple")
            Text("Banana").probe("banana")
        } header: {
            Text("Fruits").probe("fruits")
        } footer: {
            Text("Footer").probe("footer")
        }
        Text("Top").probe("top")
        Text("Bottom").probe("bottom")
        Section("Vegetables") {
            ForEach(["Carrot", "Leek"], id: \.self) { Text($0).probe($0.lowercased()) }
        }
    }
}

struct ValuesContent: View {
    var body: some View {
        Text("One").probe("one")
        Text("Two").containerValue(\.fixtureHighlighted, true).probe("two")
        Text("Three").tag(30).probe("three")
        Group {
            Text("A").probe("a")
            Text("B").probe("b")
        }
        .containerValue(\.fixtureHighlighted, true)
        .tag(12)
    }
}
