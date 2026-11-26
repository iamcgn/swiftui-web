// `EnvironmentValues.undoManager`: the window's undo manager, one for the app (a browser page
// is one window), so a view's `undoManager?.registerUndo(withTarget:handler:)` records steps that
// `undo()` and `redo()` replay.
#if !os(WASI)
import Foundation
#endif
import WebFoundation   // Foundation's UndoManager on Apple platforms, WebFoundation's on wasm and Linux

/// An undo manager held where Sendable values must be (Foundation's is not Sendable).
package final class _UndoManagerBox: @unchecked Sendable {
    package let manager: UndoManager
    package init(_ manager: UndoManager) { self.manager = manager }
    /// The app's undo manager, made the first time a view reads it. From the macOS 26 SDK on,
    /// Foundation's UndoManager is main-actor isolated, so it is made on the main thread.
    static let shared = make()

    private static func make() -> _UndoManagerBox {
        #if canImport(Darwin)
        if Thread.isMainThread { return MainActor.assumeIsolated { _UndoManagerBox(UndoManager()) } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { _UndoManagerBox(UndoManager()) } }
        #else
        return _UndoManagerBox(UndoManager())
        #endif
    }
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
