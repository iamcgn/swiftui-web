// Apple's Security framework for the web (decision 0021, the Ember app's `Keychain`): the
// keychain item functions an app calls through Core Foundation dictionaries — `SecItemAdd`,
// `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete` with the `kSec*` keys — over a store
// the host supplies (`_SecurityHost`: the browser keeps generic-password items in
// localStorage, origin-bound like every other key there; nothing else is a keychain). Only
// the wasm SDK has no Security module, so the file is empty elsewhere; the Apps package links
// this product for wasm alone.
//
// Core Foundation is not in the wasm SDK either: `CFDictionary` is the Swift dictionary an
// app writes `as CFDictionary` (an identity coercion here, a bridge on Darwin), `CFString` is
// `String`, `CFTypeRef` is `AnyObject` (the copied value comes back boxed, so the app's
// `result as? Data` succeeds as it does with an `NSData`).
#if os(WASI)
import WebFoundation

public typealias CFString = String
public typealias CFDictionary = [String: Any]
public typealias CFTypeRef = AnyObject
public typealias OSStatus = Int32
public typealias CFBoolean = Bool
public typealias CFNumber = Int

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

public let kSecAttrAccessibleWhenUnlocked: CFString = "ak"
public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ck"
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly: CFString = "aku"
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: CFString = "cku"
public let kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: CFString = "akpu"

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
            ? [kSecAttrAccount, kSecAttrServer, kSecAttrAccessGroup]
            : [kSecAttrAccount, kSecAttrService, kSecAttrAccessGroup]
        return ([itemClass] + keys.map { (attributes[$0] as? String) ?? "" }).joined(separator: "\u{1F}")
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
            case let number as Int: lines.append("\(key)=\(number)")
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
        let attributeKeys: Set<String> = [kSecAttrAccount, kSecAttrService, kSecAttrServer, kSecAttrLabel, kSecAttrAccessGroup, kSecAttrGeneric, kSecAttrDescription, kSecAttrComment]
        return identities().compactMap { id in
            guard id.hasPrefix(itemClass + "\u{1F}"), let item = read(id) else { return nil }
            for key in attributeKeys {
                guard let wanted = query[key] else { continue }
                let stored = item[key]
                if let wanted = wanted as? String { if stored as? String != wanted { return nil } }
                else if let wanted = wanted as? Data { if stored as? Data != wanted { return nil } }
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
