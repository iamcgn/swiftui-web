// Symbols on the web: the symbol effects, as Apple's Symbols framework declares them
// (`SymbolEffect`, `BounceSymbolEffect`, `DrawOnSymbolEffect`, `SymbolEffectOptions` and the
// rest). They live in the SwiftUI runtime, which plays them on symbol images, so this module
// re-exports it: a file that imports Symbols (ButtonKit's symbol-effect button styles) names
// them as on iOS.
@_exported import SwiftUIWebCore
