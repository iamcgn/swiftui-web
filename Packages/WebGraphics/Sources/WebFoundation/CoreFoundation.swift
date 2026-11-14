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

/// A `CFError`'s domain, code and user info (a `CFError` is an `NSError`).
public typealias CFErrorDomain = CFString
public func CFErrorGetDomain(_ err: CFError!) -> CFErrorDomain! { err.domain }
public func CFErrorGetCode(_ err: CFError!) -> CFIndex { err.code }
public func CFErrorCopyUserInfo(_ err: CFError!) -> CFDictionary! { err.userInfo }
public func CFErrorCopyDescription(_ err: CFError!) -> CFString! { err.localizedDescription }

/// A Core Foundation type's identifier: what `CFGetTypeID` answers for an object, compared with
/// a type's own (`CFGetTypeID(number) == CFBooleanGetTypeID()` tells a JSON boolean from the
/// integers 0 and 1, as RevenueCat's JSON encoding does). The values are this module's own.
public typealias CFTypeID = UInt
public func CFStringGetTypeID() -> CFTypeID { 7 }
public func CFNullGetTypeID() -> CFTypeID { 16 }
public func CFDictionaryGetTypeID() -> CFTypeID { 18 }
public func CFArrayGetTypeID() -> CFTypeID { 19 }
public func CFDataGetTypeID() -> CFTypeID { 20 }
public func CFBooleanGetTypeID() -> CFTypeID { 21 }
public func CFNumberGetTypeID() -> CFTypeID { 22 }
public func CFURLGetTypeID() -> CFTypeID { 29 }
public func CFErrorGetTypeID() -> CFTypeID { 30 }
public func CFDateGetTypeID() -> CFTypeID { 42 }

/// The Core Foundation type the object stands for: a number holding a boolean is a `CFBoolean`,
/// any other number a `CFNumber`, a string a `CFString`, and so on; 1 for any other object.
public func CFGetTypeID(_ cf: CFTypeRef!) -> CFTypeID {
    guard let cf else { return CFNullGetTypeID() }
    if let number = cf as? NSNumber {
        return number.objCType.pointee == CChar(UInt8(ascii: "c")) ? CFBooleanGetTypeID() : CFNumberGetTypeID()
    }
    switch cf {
    case is Bool: return CFBooleanGetTypeID()
    case is Int, is Int8, is Int16, is Int32, is Int64, is UInt, is UInt8, is UInt16, is UInt32, is UInt64,
         is Double, is Float: return CFNumberGetTypeID()
    case is NSString, is String: return CFStringGetTypeID()
    case is NSError: return CFErrorGetTypeID()
    case is Data: return CFDataGetTypeID()
    case is URL: return CFURLGetTypeID()
    case is Date: return CFDateGetTypeID()
    default: return 1
    }
}

// Implicitly unwrapped, as Apple's Swift overlay declares them.
public let kCFBooleanTrue: CFBoolean! = true
public let kCFBooleanFalse: CFBoolean! = false
#endif
