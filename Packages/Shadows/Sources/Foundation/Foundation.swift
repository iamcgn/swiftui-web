// `import Foundation` on wasm (decision 0021): WebFoundation's value types (decision 0017) and
// the modules Apple's Foundation re-exports, so an app file that imports Foundation beside
// SwiftUI sees one `URL`, one `Data`, libm's functions, `@Observable`, `DispatchQueue` and
// Combine's names. Linked by an app's Package.swift, never by this project's own targets.
#if os(WASI)
@_exported import WebFoundation
@_exported import WebFoundationFormats
@_exported import WASILibc
@_exported import Observation
@_exported import Combine
// Apple's Foundation brings CoreGraphics' `CGFloat` and geometry types with it: a package file
// that imports only Foundation names `CGFloat` (Kingfisher, the sweep's package build).
@_exported import CoreGraphics
#if CoreData
// The `CoreData` trait (decision 0024): Apple's Foundation declares `NSPredicate`,
// `NSSortDescriptor` and `NSExpression`, which live in WebCoreData here.
@_exported import WebCoreData
#endif
#if DecimalFormatting
// The `DecimalFormatting` trait: `Decimal.formatted` and `Decimal.FormatStyle`, kept out of apps
// that never name Decimal, since naming it links Foundation's Decimal (3.4 MB).
@_exported import WebDecimalFormats
#endif
#endif

#if os(WASI)
// The bridging casts `error as NSError` and `nsError as Error` compile to calls of these two
// functions, which the compiler looks up in the module named `Foundation` (decision 0021, the
// Ember app). An `NSError` is itself; any other error becomes one with the Swift error domain,
// its description in the user info, as Foundation bridges an error without a domain of its own.
public func _convertErrorToNSError(_ error: any Error) -> NSError {
    // `error as? NSError` is the bridge being defined; through `Any` the cast is a plain one.
    let value: Any = error
    if let nsError = value as? NSError { return nsError }
    if let custom = error as? any CustomNSError {
        // A `CustomNSError` names its own domain, code and user info, as on Apple platforms.
        return NSError(domain: type(of: custom).errorDomain, code: custom.errorCode, userInfo: custom.errorUserInfo)
    }
    return NSError(domain: "\(type(of: error))", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription, "NSUnderlyingError": error])
}

public func _convertNSErrorToError(_ error: NSError?) -> any Error {
    if let underlying = error?.userInfo["NSUnderlyingError"] as? any Error { return underlying }
    return error ?? NSError(domain: "NSCocoaErrorDomain", code: 0)
}
#endif
