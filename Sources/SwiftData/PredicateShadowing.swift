// Foundation imported directly by this module, so its `Predicate` is shadowed by this one for a
// file that imports both (a declaration shadows those of the modules its own module imports):
// an app's `func predicateToday() -> Predicate<Todo>` names this one, the type `#Predicate`
// makes. Its own file: in SwiftData.swift, FoundationEssentials beside WebFoundation would make
// WebFoundation's stand-ins (`Data`, `URL`) ambiguous there.
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
