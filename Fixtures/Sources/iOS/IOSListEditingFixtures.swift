// iOS list editing (`ios/list/editing`): a list in edit mode shows delete circles and reorder
// grips on the rows whose `ForEach` has `onDelete` and `onMove`, and nothing on the others;
// rendered on the iPhone SE simulator (decision 0015) and reproduced by the runtime's iOS
// profile (Docs/elements/List.md, Docs/elements/iOS.md).
import SwiftUI
import FixtureKit

@Observable
public final class IOSEditingModel {
    public var items = ["Apple", "Banana", "Cherry"]
    public init() {}
}

public enum IOSListEditingFixtures {
    /// Edit mode: deletable and movable rows, then deletable-only rows, then plain rows.
    public static let editing = Fixture(
        "ios/list/editing", size: CGSize(width: 320, height: 420),
        model: { IOSEditingModel() },
        steps: []
    ) { model in
        List {
            Section("Editable") {
                ForEach(model.items, id: \.self) { item in
                    Text(item).probe(item.lowercased())
                }
                .onDelete { model.items.remove(atOffsets: $0) }
                .onMove { model.items.move(fromOffsets: $0, toOffset: $1) }
            }
            Section("Deletable") {
                ForEach(["Date"], id: \.self) { item in
                    Text(item).probe("date")
                }
                .onDelete { _ in }
            }
            Section("Fixed") {
                Text("Detail").probe("fixed")
            }
        }
        .environment(\.editMode, .constant(.active))
        .probe("list")
    }.platform(.iOS)

    public static let all: [Fixture] = [editing]
}
