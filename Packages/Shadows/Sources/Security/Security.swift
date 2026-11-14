// Apple's Security framework for the web (decision 0021, the Ember app's `Keychain`): the
// keychain item functions an app calls through Core Foundation dictionaries — `SecItemAdd`,
// `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete` with the `kSec*` keys — over a store
// the host supplies (`_SecurityHost`: the browser keeps generic-password items in
// localStorage, origin-bound like every other key there; nothing else is a keychain). Only
// the wasm SDK has no Security module, so the file is empty elsewhere; the Apps package links
// this product for wasm alone.
//
// Core Foundation is not in the wasm SDK either: its names are WebFoundation's
// (CoreFoundation.swift), re-exported here as Apple's Security re-exports Core Foundation.
// `CFDictionary` is the Swift dictionary an app writes `as CFDictionary` (an identity coercion
// here, a bridge on Darwin), `CFString` is `String`, `CFTypeRef` is `AnyObject` (the copied
// value comes back boxed, so the app's `result as? Data` succeeds as it does with an `NSData`).
#if os(WASI)
@_exported import CoreFoundation

// MARK: - Item classes and attribute keys (the CFString constants, by their C names)

public let kSecClass: CFString = "class"
public let kSecClassGenericPassword: CFString = "genp"
public let kSecClassInternetPassword: CFString = "inet"
public let kSecClassCertificate: CFString = "cert"
public let kSecClassKey: CFString = "keys"
public let kSecClassIdentity: CFString = "idnt"

public let kSecAttrAccount: CFString = "acct"
public let kSecAttrService: CFString = "svce"
public let kSecAttrServer: CFString = "srvr"
public let kSecAttrLabel: CFString = "labl"
public let kSecAttrDescription: CFString = "desc"
public let kSecAttrComment: CFString = "icmt"
public let kSecAttrGeneric: CFString = "gena"
public let kSecAttrAccessGroup: CFString = "agrp"
public let kSecAttrSynchronizable: CFString = "sync"
public let kSecAttrAccessible: CFString = "pdmn"
public let kSecAttrCreationDate: CFString = "cdat"
public let kSecAttrModificationDate: CFString = "mdat"
public let kSecAttrCreator: CFString = "crtr"
public let kSecAttrType: CFString = "type"
public let kSecAttrIsInvisible: CFString = "invi"
public let kSecAttrIsNegative: CFString = "nega"
public let kSecAttrAccessControl: CFString = "accc"

// Internet passwords: the server's protocol, port, path, security domain and authentication
// type join the account and server as the item's identity.
public let kSecAttrSecurityDomain: CFString = "sdmn"
public let kSecAttrProtocol: CFString = "ptcl"
public let kSecAttrAuthenticationType: CFString = "atyp"
public let kSecAttrPort: CFString = "port"
public let kSecAttrPath: CFString = "path"

public let kSecAttrProtocolFTP: CFString = "ftp "
public let kSecAttrProtocolFTPAccount: CFString = "ftpa"
public let kSecAttrProtocolHTTP: CFString = "http"
public let kSecAttrProtocolIRC: CFString = "irc "
public let kSecAttrProtocolNNTP: CFString = "nntp"
public let kSecAttrProtocolPOP3: CFString = "pop3"
public let kSecAttrProtocolSMTP: CFString = "smtp"
public let kSecAttrProtocolSOCKS: CFString = "sox "
public let kSecAttrProtocolIMAP: CFString = "imap"
public let kSecAttrProtocolLDAP: CFString = "ldap"
public let kSecAttrProtocolAppleTalk: CFString = "atlk"
public let kSecAttrProtocolAFP: CFString = "afp "
public let kSecAttrProtocolTelnet: CFString = "teln"
public let kSecAttrProtocolSSH: CFString = "ssh "
public let kSecAttrProtocolFTPS: CFString = "ftps"
public let kSecAttrProtocolHTTPS: CFString = "htps"
public let kSecAttrProtocolHTTPProxy: CFString = "htpx"
public let kSecAttrProtocolHTTPSProxy: CFString = "htsx"
public let kSecAttrProtocolFTPProxy: CFString = "ftpx"
public let kSecAttrProtocolSMB: CFString = "smb "
public let kSecAttrProtocolRTSP: CFString = "rtsp"
public let kSecAttrProtocolRTSPProxy: CFString = "rtsx"
public let kSecAttrProtocolDAAP: CFString = "daap"
public let kSecAttrProtocolEPPC: CFString = "eppc"
public let kSecAttrProtocolIPP: CFString = "ipp "
public let kSecAttrProtocolNNTPS: CFString = "ntps"
public let kSecAttrProtocolLDAPS: CFString = "ldps"
public let kSecAttrProtocolTelnetS: CFString = "tels"
public let kSecAttrProtocolIMAPS: CFString = "imps"
public let kSecAttrProtocolIRCS: CFString = "ircs"
public let kSecAttrProtocolPOP3S: CFString = "pops"

public let kSecAttrAuthenticationTypeNTLM: CFString = "ntlm"
public let kSecAttrAuthenticationTypeMSN: CFString = "msna"
public let kSecAttrAuthenticationTypeDPA: CFString = "dpaa"
public let kSecAttrAuthenticationTypeRPA: CFString = "rpaa"
public let kSecAttrAuthenticationTypeHTTPBasic: CFString = "http"
public let kSecAttrAuthenticationTypeHTTPDigest: CFString = "httd"
public let kSecAttrAuthenticationTypeHTMLForm: CFString = "form"
public let kSecAttrAuthenticationTypeDefault: CFString = "dflt"

public let kSecAttrAccessibleWhenUnlocked: CFString = "ak"
public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ck"
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly: CFString = "aku"
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: CFString = "cku"
public let kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: CFString = "akpu"
// Deprecated on Apple platforms, still named by keychain wrappers (SwiftKeychainWrapper).
public let kSecAttrAccessibleAlways: CFString = "dk"
public let kSecAttrAccessibleAlwaysThisDeviceOnly: CFString = "dku"

public let kSecValueData: CFString = "v_Data"
public let kSecValueRef: CFString = "v_Ref"
public let kSecValuePersistentRef: CFString = "v_PersistentRef"

public let kSecReturnData: CFString = "r_Data"
public let kSecReturnAttributes: CFString = "r_Attributes"
public let kSecReturnRef: CFString = "r_Ref"
public let kSecReturnPersistentRef: CFString = "r_PersistentRef"

public let kSecMatchLimit: CFString = "m_Limit"
public let kSecMatchLimitOne: CFString = "m_LimitOne"
public let kSecMatchLimitAll: CFString = "m_LimitAll"

public let kSecUseDataProtectionKeychain: CFString = "nleg"
public let kSecAttrSynchronizableAny: CFString = "syna"

// Asking the user: a page has no keychain prompt, so these are accepted and change nothing.
public let kSecUseOperationPrompt: CFString = "u_OpPrompt"
public let kSecUseNoAuthenticationUI: CFString = "u_NoAuthUI"
public let kSecUseAuthenticationUI: CFString = "u_AuthUI"
public let kSecUseAuthenticationUIAllow: CFString = "u_AuthUIA"
public let kSecUseAuthenticationUIFail: CFString = "u_AuthUIF"
public let kSecUseAuthenticationUISkip: CFString = "u_AuthUIS"
public let kSecUseAuthenticationContext: CFString = "u_AuthCtx"

// MARK: - Access control

/// When an item may be read and what must be shown first. Kept with the item; the browser
/// asks for no presence, biometry or passcode, so it gates nothing here.
public final class SecAccessControl: @unchecked Sendable {
    public let protection: CFTypeRef
    public let flags: SecAccessControlCreateFlags
    fileprivate init(protection: CFTypeRef, flags: SecAccessControlCreateFlags) {
        self.protection = protection
        self.flags = flags
    }
}

public struct SecAccessControlCreateFlags: OptionSet, Hashable, Sendable {
    public let rawValue: CFOptionFlags
    public init(rawValue: CFOptionFlags) { self.rawValue = rawValue }
    public static let userPresence = SecAccessControlCreateFlags(rawValue: 1 << 0)
    public static let biometryAny = SecAccessControlCreateFlags(rawValue: 1 << 1)
    public static let touchIDAny = biometryAny
    public static let biometryCurrentSet = SecAccessControlCreateFlags(rawValue: 1 << 3)
    public static let touchIDCurrentSet = biometryCurrentSet
    public static let devicePasscode = SecAccessControlCreateFlags(rawValue: 1 << 4)
    public static let watch = SecAccessControlCreateFlags(rawValue: 1 << 5)
    public static let companion = watch
    public static let or = SecAccessControlCreateFlags(rawValue: 1 << 14)
    public static let and = SecAccessControlCreateFlags(rawValue: 1 << 15)
    public static let privateKeyUsage = SecAccessControlCreateFlags(rawValue: 1 << 30)
    public static let applicationPassword = SecAccessControlCreateFlags(rawValue: 1 << 31)
}

/// An access control for `protection` (one of the `kSecAttrAccessible` values) and `flags`.
public func SecAccessControlCreateWithFlags(_ allocator: CFAllocator?, _ protection: CFTypeRef,
                                            _ flags: SecAccessControlCreateFlags,
                                            _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> SecAccessControl? {
    SecAccessControl(protection: protection, flags: flags)
}

// MARK: - Result codes

public let errSecSuccess: OSStatus = 0
public let errSecUnimplemented: OSStatus = -4
public let errSecParam: OSStatus = -50
public let errSecAllocate: OSStatus = -108
public let errSecNotAvailable: OSStatus = -25291
public let errSecDuplicateItem: OSStatus = -25299
public let errSecItemNotFound: OSStatus = -25300
public let errSecInteractionNotAllowed: OSStatus = -25308
public let errSecDecode: OSStatus = -26275
public let errSecAuthFailed: OSStatus = -25293
public let errSecMissingEntitlement: OSStatus = -34018
public let errSecInvalidValue: OSStatus = -67694

/// A human-readable string for the result code.
public func SecCopyErrorMessageString(_ status: OSStatus, _ reserved: UnsafeMutableRawPointer?) -> CFString? {
    switch status {
    case errSecSuccess: return "No error."
    case errSecParam: return "One or more parameters passed to a function were not valid."
    case errSecDuplicateItem: return "The specified item already exists in the keychain."
    case errSecItemNotFound: return "The specified item could not be found in the keychain."
    case errSecNotAvailable: return "No keychain is available. You may need to restart your computer."
    case errSecUnimplemented: return "Function or operation not implemented."
    default: return "OSStatus \(status)"
    }
}

// MARK: - The item store

/// The keychain: items by class and identifying attributes, each a dictionary of attributes
/// with its data. Persisted through the host as one JSON document per item.
enum _Keychain {
    /// The attributes that identify an item of each class, as the keychain's primary keys.
    static func identity(of attributes: CFDictionary) -> String {
        let itemClass = attributes[kSecClass] as? String ?? kSecClassGenericPassword
        let keys: [String] = itemClass == kSecClassInternetPassword
            ? [kSecAttrAccount, kSecAttrServer, kSecAttrAccessGroup, kSecAttrProtocol, kSecAttrPort, kSecAttrPath,
               kSecAttrSecurityDomain, kSecAttrAuthenticationType]
            : [kSecAttrAccount, kSecAttrService, kSecAttrAccessGroup]
        return ([itemClass] + keys.map { attributes[$0].map { "\($0)" } ?? "" }).joined(separator: "\u{1F}")
    }

    nonisolated(unsafe) private static var memory: [String: String] = [:]
    nonisolated(unsafe) private static var index: Set<String> = []
    private static let indexKey = "\u{1F}index"

    private static func load(_ key: String) -> String? {
        if let store = _SecurityHost.store { return store.load(key) }
        return memory[key]
    }

    private static func save(_ key: String, _ value: String?) {
        if let store = _SecurityHost.store { store.save(key, value) } else { memory[key] = value }
    }

    /// Every stored item's identity (the host keeps them under separate keys).
    static func identities() -> [String] {
        (load(indexKey) ?? "").split(separator: "\u{1E}").map(String.init)
    }

    private static func setIdentities(_ ids: [String]) {
        save(indexKey, ids.isEmpty ? nil : ids.joined(separator: "\u{1E}"))
    }

    /// An item's attributes: strings, booleans and its data (base64), one line per attribute.
    static func read(_ id: String) -> [String: Any]? {
        guard let text = load(id) else { return nil }
        var item: [String: Any] = [:]
        for line in text.split(separator: "\n") {
            guard let split = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<split])
            let value = String(line[line.index(after: split)...])
            if key == kSecValueData {
                item[key] = Data(base64Encoded: value) ?? Data()
            } else if value == "\u{1D}true" || value == "\u{1D}false" {
                item[key] = value == "\u{1D}true"
            } else if value.hasPrefix("\u{1D}#"), let number = Int(value.dropFirst(2)) {
                item[key] = number
            } else {
                item[key] = value
            }
        }
        return item
    }

    static func write(_ id: String, _ item: [String: Any]) {
        var lines: [String] = []
        for (key, value) in item.sorted(by: { $0.key < $1.key }) {
            switch value {
            case let data as Data: lines.append("\(key)=\(data.base64EncodedString())")
            case let flag as Bool: lines.append("\(key)=\u{1D}\(flag)")
            case let string as String: lines.append("\(key)=\(string)")
            case let number as Int: lines.append("\(key)=\u{1D}#\(number)")
            default: continue
            }
        }
        save(id, lines.joined(separator: "\n"))
        var ids = identities()
        if !ids.contains(id) { ids.append(id); setIdentities(ids) }
    }

    static func remove(_ id: String) {
        save(id, nil)
        setIdentities(identities().filter { $0 != id })
    }

    /// The stored items a query's class and attributes match (every attribute given must equal).
    static func matches(_ query: CFDictionary) -> [(id: String, item: [String: Any])] {
        let itemClass = query[kSecClass] as? String ?? kSecClassGenericPassword
        let attributeKeys: Set<String> = [kSecAttrAccount, kSecAttrService, kSecAttrServer, kSecAttrLabel, kSecAttrAccessGroup, kSecAttrGeneric,
                                          kSecAttrDescription, kSecAttrComment, kSecAttrProtocol, kSecAttrPort, kSecAttrPath,
                                          kSecAttrSecurityDomain, kSecAttrAuthenticationType, kSecAttrType, kSecAttrCreator]
        return identities().compactMap { id in
            guard id.hasPrefix(itemClass + "\u{1F}"), let item = read(id) else { return nil }
            for key in attributeKeys {
                guard let wanted = query[key] else { continue }
                let stored = item[key]
                if let wanted = wanted as? String { if stored as? String != wanted { return nil } }
                else if let wanted = wanted as? Data { if stored as? Data != wanted { return nil } }
                else if let wanted = wanted as? Int { if stored as? Int != wanted { return nil } }
            }
            return (id, item)
        }
    }

    /// What `SecItemCopyMatching` returns for an item: its data, its attributes, or both.
    static func result(for item: [String: Any], query: CFDictionary) -> AnyObject? {
        let wantsData = query[kSecReturnData] as? Bool ?? false
        let wantsAttributes = query[kSecReturnAttributes] as? Bool ?? false
        if wantsAttributes {
            var attributes = item
            if !wantsData { attributes[kSecValueData] = nil }
            return attributes as AnyObject
        }
        if wantsData { return (item[kSecValueData] as? Data ?? Data()) as AnyObject }
        // Neither asked: a reference, which this keychain has no object for — the attributes.
        return item as AnyObject
    }
}

// MARK: - The functions

/// Adds one or more items to a keychain.
@discardableResult
public func SecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard attributes[kSecClass] is String else { return errSecParam }
    let id = _Keychain.identity(of: attributes)
    if _Keychain.read(id) != nil { return errSecDuplicateItem }
    var item: [String: Any] = [:]
    for (key, value) in attributes where !key.hasPrefix("r_") && key != kSecMatchLimit {
        item[key] = value
    }
    if item[kSecValueData] == nil { item[kSecValueData] = Data() }
    _Keychain.write(id, item)
    if let result { result.pointee = _Keychain.result(for: item, query: attributes) }
    return errSecSuccess
}

/// Returns one or more keychain items that match a search query.
@discardableResult
public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard query[kSecClass] is String else { return errSecParam }
    let matches = _Keychain.matches(query)
    guard let first = matches.first else { return errSecItemNotFound }
    if let result {
        if query[kSecMatchLimit] as? String == kSecMatchLimitAll {
            result.pointee = matches.map { _Keychain.result(for: $0.item, query: query) as Any } as AnyObject
        } else {
            result.pointee = _Keychain.result(for: first.item, query: query)
        }
    }
    return errSecSuccess
}

/// Modifies items that match a search query.
@discardableResult
public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
    let matches = _Keychain.matches(query)
    guard !matches.isEmpty else { return errSecItemNotFound }
    for (id, item) in matches {
        var updated = item
        for (key, value) in attributesToUpdate { updated[key] = value }
        let newID = _Keychain.identity(of: updated)
        if newID != id { _Keychain.remove(id) }
        _Keychain.write(newID, updated)
    }
    return errSecSuccess
}

/// Deletes items that match a search query.
@discardableResult
public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    let matches = _Keychain.matches(query)
    guard !matches.isEmpty else { return errSecItemNotFound }
    for (id, _) in matches { _Keychain.remove(id) }
    return errSecSuccess
}
#endif
