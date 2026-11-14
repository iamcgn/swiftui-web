// The module Apple's SDK pairs with Translation and SwiftUI (the cross-import overlay that holds
// `translationTask` and `translationPresentation`). Apps test for it with
// `#if canImport(_Translation_SwiftUI)` (Ice Cubes); here those modifiers are in Translation
// itself, which this re-exports.
@_exported import Translation
