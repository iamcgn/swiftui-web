import SwiftUI
import FixtureKit

public struct FoodGroup: Identifiable, Sendable {
    public let id: String
    public let items: [String]
}

public enum SectionFixtures {
    static let groups = [FoodGroup(id: "Fruits", items: ["Apple", "Banana"]), FoodGroup(id: "Vegetables", items: ["Carrot", "Leek"])]

    public static let vstack = Fixture("section/vstack", size: CGSize(width: 300, height: 250)) {
        VStack(alignment: .leading) {
            Section {
                Text("Apple").probe("apple")
                Text("Banana").probe("banana")
            } header: {
                Text("Fruits").probe("header")
            } footer: {
                Text("Footer").probe("footer")
            }
        }
        .probe("stack")
    }

    /// `Section("Title")` builds a `Text` header; the stack's width and the rows' y reveal its
    /// font and height.
    public static let title = Fixture("section/title", size: CGSize(width: 300, height: 250)) {
        VStack(alignment: .leading, spacing: 0) {
            Section("Fruits") {
                Text("Apple").probe("apple")
            }
            Section("Vegetables") {
                Text("Carrot").probe("carrot")
            }
        }
        .probe("stack")
    }

    public static let hstack = Fixture("section/hstack", size: CGSize(width: 300, height: 200)) {
        HStack {
            Section {
                Text("A").probe("a")
                Text("B").probe("b")
            } header: {
                Text("Header").probe("header")
            } footer: {
                Text("Footer").probe("footer")
            }
        }
        .probe("row")
    }

    public static let forEach = Fixture("section/foreach", size: CGSize(width: 300, height: 250)) {
        VStack(alignment: .leading) {
            ForEach(groups) { group in
                Section(group.id) {
                    ForEach(group.items, id: \.self) { item in
                        Text(item).probe(item)
                    }
                }
            }
        }
        .probe("stack")
    }

    /// A modifier on a `Section` applies to its header, every content view and its footer.
    public static let modifier = Fixture("section/modifier", size: CGSize(width: 300, height: 250)) {
        VStack(spacing: 0) {
            Section {
                Text("Apple").probe("apple")
            } header: {
                Text("Fruits").probe("header")
            }
            .padding()
            .probe("paddedLast")
            Section {
                Text("Banana").probe("banana")
            } footer: {
                Text("Footer").probe("footer")
            }
            .frame(width: 120, height: 30)
            .background(Color.blue)
            .probe("framedLast")
        }
        .probe("stack")
    }

    public static let mixed = Fixture("section/mixed", size: CGSize(width: 300, height: 250)) {
        VStack {
            Text("Top").probe("top")
            Section {
                Text("Apple").probe("apple")
            }
            Section {
                Text("Banana").probe("banana")
            } footer: {
                Text("Footer").probe("footer")
            }
            Text("Bottom").probe("bottom")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [vstack, title, hstack, forEach, modifier, mixed]
}
