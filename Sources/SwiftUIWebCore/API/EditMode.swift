// Edit mode (Docs/elements/List.md): `EditMode`, the environment's `editMode` binding and
// `EditButton`. A list in edit mode shows iOS's delete circles and reorder grips on the rows
// whose `ForEach` has `onDelete` / `onMove`.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A mode that indicates whether the user can edit a view's content.
public enum EditMode: Sendable, Hashable {
    case inactive
    case transient
    case active

    /// Whether the view is being edited (`active` or `transient`).
    public var isEditing: Bool { self != .inactive }
}

package struct EditModeKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: Binding<EditMode>? = nil
}

extension EnvironmentValues {
    /// A binding to whether the user can edit the contents of a view associated with this environment.
    public var editMode: Binding<EditMode>? {
        get { self[EditModeKey.self] }
        set { self[EditModeKey.self] = newValue }
    }
}

/// A button that toggles the edit mode environment value: "Edit" while inactive, "Done" while editing.
public struct EditButton: View {
    @Environment(\.editMode) private var editMode

    public init() {}

    public var body: some View {
        let editing = editMode?.wrappedValue.isEditing ?? false
        Button(editing ? "Done" : "Edit") {
            editMode?.wrappedValue = editing ? .inactive : .active
        }
    }
}
