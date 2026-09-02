import SwiftUI
import FixtureKit

public struct Fruit: Identifiable, Sendable {
    public let id: String
    public var name: String { id }
}

/// A row whose state is seeded from its item once: reconciliation by id must keep it across
/// inserts, mutations, moves and removals (`foreach/identity`).
struct IdentityRow: View {
    let item: IdentityItem
    @State private var width: CGFloat

    init(item: IdentityItem) {
        self.item = item
        _width = State(initialValue: item.width)
    }

    var body: some View {
        Color.blue.frame(width: width, height: 20).probe("row-\(item.id)")
    }
}

public struct IdentityItem: Identifiable, Sendable {
    public let id: String
    public var width: CGFloat
}

@Observable
public final class IdentityModel {
    public var items = [IdentityItem(id: "a", width: 60), IdentityItem(id: "b", width: 100), IdentityItem(id: "c", width: 140)]
    public init() {}
}

/// `ForEach($items)` hands each row a binding to its element.
struct BindingRows: View {
    @State private var fruits = [Fruit(id: "Apple"), Fruit(id: "Banana")]

    var body: some View {
        VStack(alignment: .leading) {
            ForEach($fruits) { $fruit in
                Text(fruit.name).probe(fruit.name)
            }
        }
        .probe("stack")
    }
}

public enum ForEachFixtures {
    static let fruits = [Fruit(id: "Apple"), Fruit(id: "Banana"), Fruit(id: "Cherry")]
    static let greek = ["Alpha", "Beta", "Gamma"]

    public static let range = Fixture("foreach/range", size: CGSize(width: 300, height: 200)) {
        VStack(alignment: .leading) {
            Text("Top").probe("top")
            ForEach(0..<3) { index in
                Text("Row \(index)").probe("row\(index)")
            }
            Text("Bottom").probe("bottom")
        }
        .probe("stack")
    }

    public static let identifiable = Fixture("foreach/identifiable", size: CGSize(width: 300, height: 200)) {
        HStack {
            ForEach(fruits) { fruit in
                Text(fruit.name).probe(fruit.name)
            }
        }
        .probe("row")
    }

    public static let idKeyPath = Fixture("foreach/id-keypath", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 0) {
            ForEach(greek, id: \.self) { name in
                Text(name).probe(name)
            }
        }
        .probe("stack")
    }

    /// A modifier on a `ForEach` applies to every element, like `Group`; a per-element
    /// preference written under one id resolves to the last element.
    public static let modifier = Fixture("foreach/modifier", size: CGSize(width: 300, height: 260)) {
        VStack(spacing: 0) {
            ForEach(0..<2) { index in
                Text("Row \(index)").probe("padded\(index)")
            }
            .padding()
            .probe("paddedLast")
            ForEach(0..<2) { index in
                Text("Row \(index)").probe("framed\(index)")
            }
            .frame(width: 120, height: 30)
            .background(Color.blue)
            .probe("framedLast")
        }
        .probe("stack")
    }

    public static let nested = Fixture("foreach/nested", size: CGSize(width: 300, height: 200)) {
        VStack {
            ForEach(0..<2) { row in
                HStack {
                    ForEach(0..<3) { column in
                        Color.blue.frame(width: 30, height: 20).probe("cell\(row)\(column)")
                    }
                }
                .probe("row\(row)")
            }
        }
        .probe("grid")
    }

    public static let empty = Fixture("foreach/empty", size: CGSize(width: 300, height: 200)) {
        VStack {
            Text("Top").probe("top")
            ForEach([String](), id: \.self) { Text($0) }
            ForEach(0..<0) { Text("Row \($0)") }
            HStack {
                Text("A").probe("a")
                ForEach([String](), id: \.self) { Text($0) }
                Text("B").probe("b")
            }
            .probe("row")
            Text("Bottom").probe("bottom")
        }
        .probe("stack")
    }

    public static let binding = Fixture("foreach/binding", size: CGSize(width: 300, height: 200)) {
        BindingRows()
    }

    /// Behaviour: rows keep their seeded state by id across every kind of data change.
    public static let identity = Fixture(
        "foreach/identity", size: CGSize(width: 300, height: 200),
        model: { IdentityModel() },
        steps: [
            FixtureStep("insert") { $0.items.insert(IdentityItem(id: "d", width: 80), at: 0) },
            FixtureStep("mutate") { $0.items[1].width = 200 },   // "a" keeps its seeded 60
            FixtureStep("reverse") { $0.items.reverse() },
            FixtureStep("remove") { $0.items.removeAll { $0.id == "b" } },
        ]
    ) { model in
        VStack(alignment: .leading) {
            ForEach(model.items) { item in
                IdentityRow(item: item)
            }
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [range, identifiable, idKeyPath, modifier, nested, empty, binding, identity]
}
