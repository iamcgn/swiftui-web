// `EnvironmentValues.undoManager`: the window's undo manager, one for the app (a browser page
// is one window), so a view's `undoManager?.registerUndo(withTarget:handler:)` records steps that
// `undo()` and `redo()` replay.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// An undo manager held where Sendable values must be (Foundation's is not Sendable).
package final class _UndoManagerBox: @unchecked Sendable {
    package let manager: UndoManager
    package init(_ manager: UndoManager) { self.manager = manager }
    /// The app's undo manager, made the first time a view reads it.
    static let shared = _UndoManagerBox(UndoManager())
}

package struct UndoManagerOverrideKey: EnvironmentKey {
    package static let defaultValue: _UndoManagerBox? = nil
}

extension EnvironmentValues {
    /// The undo manager views in the window register their changes with.
    public var undoManager: UndoManager? { (self[UndoManagerOverrideKey.self] ?? _UndoManagerBox.shared).manager }

    /// A different undo manager for a subtree (a document's own).
    package var _undoManager: UndoManager? {
        get { self[UndoManagerOverrideKey.self]?.manager }
        set { self[UndoManagerOverrideKey.self] = newValue.map(_UndoManagerBox.init) }
    }
}
