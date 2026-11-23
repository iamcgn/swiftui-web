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

/// A Core Foundation string encoding (`CFStringBuiltInEncodings`' raw values), and the
/// conversions between it, Foundation's `String.Encoding` raw values and IANA charset names
/// (OpenGraph reads a page's `charset` this way) for the encodings strings convert through here.
public typealias CFStringEncoding = UInt32
public let kCFStringEncodingInvalidId: CFStringEncoding = 0xFFFF_FFFF

/// (CF encoding, Foundation encoding, IANA name) for each encoding carried.
private let _cfEncodings: [(CFStringEncoding, UInt, String)] = [
    (0x0800_0100, 4, "utf-8"), (0x0600, 1, "us-ascii"), (0x0201, 5, "iso-8859-1"), (0x0500, 12, "windows-1252"),
    (0x0100, 10, "utf-16"), (0x1000_0100, 0x9000_0100, "utf-16be"), (0x1400_0100, 0x9400_0100, "utf-16le"),
    (0x0C00_0100, 0x8C00_0100, "utf-32"), (0x1800_0100, 0x9800_0100, "utf-32be"), (0x1C00_0100, 0x9C00_0100, "utf-32le"),
]
private let _ianaAliases: [String: String] = ["utf8": "utf-8", "ascii": "us-ascii", "latin1": "iso-8859-1", "iso_8859-1": "iso-8859-1",
                                              "cp1252": "windows-1252", "utf16": "utf-16", "utf32": "utf-32"]

/// The encoding an IANA charset name (`"UTF-8"`, `"iso-8859-1"`) names, ignoring case;
/// `kCFStringEncodingInvalidId` for a name it does not know.
public func CFStringConvertIANACharSetNameToEncoding(_ theString: CFString!) -> CFStringEncoding {
    let name = theString.lowercased()
    let canonical = _ianaAliases[name] ?? name
    return _cfEncodings.first { $0.2 == canonical }?.0 ?? kCFStringEncodingInvalidId
}
/// The IANA charset name of an encoding, nil for one it does not know.
public func CFStringConvertEncodingToIANACharSetName(_ encoding: CFStringEncoding) -> CFString! {
    _cfEncodings.first { $0.0 == encoding }?.2
}
/// The `String.Encoding` raw value of a CF encoding (`kCFStringEncodingInvalidId` for one it does not know).
public func CFStringConvertEncodingToNSStringEncoding(_ encoding: CFStringEncoding) -> UInt {
    _cfEncodings.first { $0.0 == encoding }?.1 ?? UInt(kCFStringEncodingInvalidId)
}
/// The CF encoding of a `String.Encoding` raw value (`kCFStringEncodingInvalidId` for one it does not know).
public func CFStringConvertNSStringEncodingToEncoding(_ encoding: UInt) -> CFStringEncoding {
    _cfEncodings.first { $0.1 == encoding }?.0 ?? kCFStringEncodingInvalidId
}

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

/// A URL from a string, relative to `baseURL` when given (SwiftSoup's URL parsing on Apple
/// platforms); nil for a string that isn't a URL, as Core Foundation's is.
public func CFURLCreateWithString(_ allocator: CFAllocator!, _ URLString: CFString!, _ baseURL: CFURL!) -> CFURL! {
    guard let URLString else { return nil }
    return URL(string: URLString, relativeTo: baseURL)
}

/// The URL's string, as it was given (relative to its base, if it has one).
public func CFURLGetString(_ anURL: CFURL!) -> CFString! { anURL?.relativeString }

/// The URL resolved against its base.
public func CFURLCopyAbsoluteURL(_ relativeURL: CFURL!) -> CFURL! { relativeURL?.absoluteURL }
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

/// A range of a CF string or array: where it starts and how many it covers (Core Text's string
/// ranges, where a length of 0 runs to the end).
public struct CFRange: Equatable, Sendable {
    public var location: CFIndex
    public var length: CFIndex
    public init() { location = 0; length = 0 }
    public init(location: CFIndex, length: CFIndex) {
        self.location = location
        self.length = length
    }
}
public func CFRangeMake(_ loc: CFIndex, _ len: CFIndex) -> CFRange { CFRange(location: loc, length: len) }

/// An attributed string, which an app passes `as CFAttributedString` (an identity coercion here).
public typealias CFAttributedString = NSAttributedString
public typealias CFMutableAttributedString = NSMutableAttributedString
/// The length in UTF-16 units.
public func CFAttributedStringGetLength(_ aStr: CFAttributedString!) -> CFIndex { aStr.length }
public func CFAttributedStringGetString(_ aStr: CFAttributedString!) -> CFString! { aStr.string }

// Implicitly unwrapped, as Apple's Swift overlay declares them.
public let kCFBooleanTrue: CFBoolean! = true
public let kCFBooleanFalse: CFBoolean! = false
#endif
