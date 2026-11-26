// `typesettingLanguage(_:isEnabled:)` takes a `Locale.Language`, which on wasm is
// WebFoundationFormats' (the `FoundationFormats` trait), so it lives here beside that module's
// re-export rather than in SwiftUIWebCore, which links only WebFoundation.
#if !os(WASI) || FoundationFormats
import SwiftUIWebCore
#if os(WASI)
import WebFoundationFormats
#elseif canImport(Darwin)
import Foundation
#else
import WebFoundation
#endif

extension View {
    /// Sets the language whose line heights and glyph forms the text in this view is set for
    /// (Mlem sets English on its titles). The browser sets each run for its own script, so the
    /// language is accepted and the text is laid out as before.
    nonisolated public func typesettingLanguage(_ language: Locale.Language, isEnabled: Bool = true) -> some View { self }
}
#endif
