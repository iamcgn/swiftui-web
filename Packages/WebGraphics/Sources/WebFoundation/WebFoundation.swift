// WebFoundation: the Foundation the substrate and the frameworks import (decision 0017).
//
// On Apple platforms and Linux it is Foundation itself. On wasm it is FoundationEssentials plus
// stand-ins for the value types whose FoundationEssentials members drag the whole library into
// the bundle: `Data`, `URL`, `Calendar`, `TimeZone`, `Locale`, `DateComponents`, `IndexPath`
// and the sort comparators (6.3 MB of wasm for a calendar, measured 2026-09-18). `Date` stays
// FoundationEssentials' (its member stands alone).
//
// FoundationEssentials is re-exported name by name: each of its top-level declarations that this
// module does not declare itself (the list is FoundationEssentials' public top-level names in
// the 6.3 toolchain; its extensions' members come with any of them). A whole-module re-export
// would also bring the names declared here a second time, and a lookup that does not shadow by
// import path sees both: `import struct Foundation.URL` (swift-openapi-runtime) was ambiguous,
// and the typealiases the Foundation shadow declared for it were a second `URL` beside this one
// in every file importing Foundation and SwiftUI, where `[URL]()` and `URL?.none` failed
// (IceCubes' Models). Here every module that reaches FoundationEssentials through this one sees
// one declaration of each name. `Expression` is left out: the name is both a struct and the
// `#Expression` macro, so a scoped import of it is ambiguous. No scoped import names a macro, so
// FoundationEssentials' `#Expression` and `#Predicate` are not re-exported either (SwiftData
// declares its own `#Predicate`). Operator methods are found through a module's own lookup
// table, which a name-by-name re-export leaves closed: EssentialsOperators.swift declares the
// ones FoundationEssentials gives its types beyond the standard library's protocols.
#if os(WASI)
@_exported import typealias FoundationEssentials.AttributeScopeCodableConfiguration
@_exported import typealias FoundationEssentials.CocoaError
@_exported import typealias FoundationEssentials.CodableAttributedStringKey
@_exported import typealias FoundationEssentials.CodableConfiguration
@_exported import typealias FoundationEssentials.CodableWithConfiguration
@_exported import protocol FoundationEssentials.ContiguousBytes
@_exported import protocol FoundationEssentials.DataProtocol
@_exported import typealias FoundationEssentials.Date
@_exported import typealias FoundationEssentials.Decimal
@_exported import protocol FoundationEssentials.DecodableAttributedStringKey
@_exported import protocol FoundationEssentials.DecodableWithConfiguration
@_exported import protocol FoundationEssentials.DecodingConfigurationProviding
@_exported import typealias FoundationEssentials.DiscontiguousAttributedSubstring
@_exported import protocol FoundationEssentials.DiscreteFormatStyle
@_exported import protocol FoundationEssentials.EncodableAttributedStringKey
@_exported import protocol FoundationEssentials.EncodableWithConfiguration
@_exported import protocol FoundationEssentials.EncodingConfigurationProviding
@_exported import protocol FoundationEssentials.FileManagerDelegate
@_exported import typealias FoundationEssentials.FileProtectionType
@_exported import protocol FoundationEssentials.MarkdownDecodableAttributedStringKey
@_exported import protocol FoundationEssentials.MutableDataProtocol
@_exported import typealias FoundationEssentials.OperatingSystemVersion
@_exported import typealias FoundationEssentials.POSIXError
@_exported import typealias FoundationEssentials.PredicateBindings
@_exported import typealias FoundationEssentials.PredicateError
@_exported import protocol FoundationEssentials.PredicateExpression
@_exported import typealias FoundationEssentials.PredicateExpressions
@_exported import typealias FoundationEssentials.ProcessInfo
@_exported import protocol FoundationEssentials.StandardPredicateExpression
@_exported import typealias FoundationEssentials.TimeInterval
@_exported import typealias FoundationEssentials.UUID
@_exported import typealias FoundationEssentials.uuid_string_t
@_exported import typealias FoundationEssentials.uuid_t
@_exported import func FoundationEssentials.pow
#if canImport(ObjectiveC)
// The interop SDK (decision 0023): Selector, NSObject and NSObjectProtocol come from the
// Objective-C runtime, as Apple's Foundation re-exports them.
@_exported import ObjectiveC
#endif
#else
@_exported import Foundation
#endif
