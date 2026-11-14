// Apple's `CoreText` module for wasm: the font manager calls a package makes to register a font
// file it downloaded or bundled (RevenueCat's paywall fonts), with their errors. A page draws
// text with the fonts the browser has loaded, and the canvas host loads the app's bundled fonts
// itself, so registering here checks that the file can be read and keeps a record of it: a
// second registration of the same file fails with `alreadyRegistered`, a missing file with
// `fileNotFound`, and unregistering a file that isn't registered with `notRegistered`, as
// Apple's do. `CTFont` and the layout types aren't here.
#if os(WASI)
@_exported import WebFoundation

/// Where a registered font is available.
public enum CTFontManagerScope: UInt32, Sendable {
    case none = 0
    case process = 1
    case persistent = 2
    case session = 3
    public static var user: CTFontManagerScope { .persistent }
}

/// The font manager's errors, with Apple's codes, in `kCTFontManagerErrorDomain`.
public enum CTFontManagerError: CFIndex, Sendable {
    case fileNotFound = 101
    case insufficientPermissions = 102
    case unrecognizedFormat = 103
    case invalidFontData = 104
    case alreadyRegistered = 105
    case exceededResourceLimit = 106
    case assetNotFound = 107
    case notRegistered = 201
    case inUse = 202
    case systemRequired = 203
    case registrationFailed = 301
    case missingEntitlement = 302
    case insufficientInfo = 303
    case cancelledByUser = 304
    case duplicatedName = 305
    case invalidFilePath = 306
    case unsupportedScope = 307
}

public let kCTFontManagerErrorDomain: CFString = "com.apple.CoreText.CTFontManagerErrorDomain"

/// The font files registered so far, by path.
nonisolated(unsafe) private var _registeredFontPaths: Set<String> = []

private func _fail(_ code: CTFontManagerError, _ url: URL, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    let failure = NSError(domain: kCTFontManagerErrorDomain, code: code.rawValue,
                          userInfo: ["CTFontManagerErrorFontURLs": [url.absoluteString]])
    error?.pointee = Unmanaged.passRetained(failure)
    return false
}

/// Registers the fonts in a file for `scope`: true when the file can be read and wasn't
/// registered already.
public func CTFontManagerRegisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope,
                                             _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    guard fontURL.isFileURL else { return _fail(.invalidFilePath, fontURL, error) }
    guard scope != .none else { return _fail(.unsupportedScope, fontURL, error) }
    let path = fontURL.standardizedFileURL.path
    guard !_registeredFontPaths.contains(path) else { return _fail(.alreadyRegistered, fontURL, error) }
    guard let data = FileManager.default.contents(atPath: path) else { return _fail(.fileNotFound, fontURL, error) }
    guard !data.isEmpty else { return _fail(.invalidFontData, fontURL, error) }
    _registeredFontPaths.insert(path)
    return true
}

/// Unregisters the fonts in a file registered with `CTFontManagerRegisterFontsForURL`.
public func CTFontManagerUnregisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope,
                                               _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    guard _registeredFontPaths.remove(fontURL.standardizedFileURL.path) != nil else { return _fail(.notRegistered, fontURL, error) }
    return true
}
#endif
