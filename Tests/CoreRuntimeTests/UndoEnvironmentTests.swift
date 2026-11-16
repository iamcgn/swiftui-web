// `EnvironmentValues.undoManager`: one undo manager for the window, and a subtree's own.
// Apple platforms only: Linux's Foundation leaves UndoManager unimplemented.
import Testing
import Foundation
import SwiftUI
import SwiftUIWebCore

#if canImport(Darwin)
@Suite @MainActor struct UndoEnvironmentTests {
    @Test func viewsShareTheWindowsUndoManager() {
        let manager = EnvironmentValues().undoManager
        #expect(manager != nil)
        #expect(manager === EnvironmentValues().undoManager)
        var document = EnvironmentValues()
        let own = UndoManager()
        document._undoManager = own
        #expect(document.undoManager === own)
    }
}
#endif
