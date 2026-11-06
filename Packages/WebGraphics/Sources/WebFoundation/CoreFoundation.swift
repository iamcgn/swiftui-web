// Core Foundation's names on wasm, which has no Core Foundation (decision 0021): packages call
// the keychain and image APIs through CF types (keychain-swift's `kCFBooleanTrue`, Alamofire's
// `CFError`, Kingfisher's `CFDictionary`), and Apple's Foundation re-exports Core Foundation, so
// they are here for `import Foundation` and for the `CoreFoundation` and `Security` shadows
// (Packages/Shadows). Each CF type is the Swift type it bridges to on Apple platforms: a
// `CFDictionary` is the dictionary an app writes `as CFDictionary` (an identity coercion here),
// a `CFString` is `String`, a `CFBoolean` is `Bool`. The clock types are in Threading.swift.
#if os(WASI)
public typealias CFTypeRef = AnyObject
public typealias CFString = String
public typealias CFDictionary = [String: Any]
public typealias CFArray = [Any]
public typealias CFData = Data
public typealias CFURL = URL
public typealias CFBoolean = Bool
public typealias CFNumber = Int
public typealias CFIndex = Int
public typealias CFError = NSError
/// A result code (Core Services' `OSStatus`, which the keychain functions return).
public typealias OSStatus = Int32
/// A bit set of options (Security's revocation flags).
public typealias CFOptionFlags = UInt

/// What allocates a CF object; every allocation here is Swift's, so callers pass nil or the
/// default.
public final class CFAllocator: @unchecked Sendable {
    fileprivate init() {}
}
public let kCFAllocatorDefault: CFAllocator! = CFAllocator()

/// The result code for success.
public let noErr: OSStatus = 0

// Implicitly unwrapped, as Apple's Swift overlay declares them.
public let kCFBooleanTrue: CFBoolean! = true
public let kCFBooleanFalse: CFBoolean! = false
#endif
