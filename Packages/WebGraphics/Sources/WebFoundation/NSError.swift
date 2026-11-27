// Foundation's `NSError` and `Error.localizedDescription` on wasm (decision 0021): there is
// no Objective-C bridge, so `NSError` is a plain error class with a domain, a code and a user
// info dictionary, and every error describes itself as Foundation's would: a `LocalizedError`
// by its `errorDescription`, an `NSError` by its user info, anything else by the operation
// sentence with its type and code. `LocalizedError` is declared here, shadowing
// FoundationEssentials' (decision 0017): naming that one's protocol descriptor extracts
// CocoaError.swift and, through it, most of FoundationEssentials (3.3 MB of the Gallery).
#if os(WASI)
/// A specialized error that provides localized messages describing the error and why it occurred.
public protocol LocalizedError: Error {
    var errorDescription: String? { get }
    var failureReason: String? { get }
    var recoverySuggestion: String? { get }
    var helpAnchor: String? { get }
}

extension LocalizedError {
    public var errorDescription: String? { nil }
    public var failureReason: String? { nil }
    public var recoverySuggestion: String? { nil }
    public var helpAnchor: String? { nil }
}

#if canImport(ObjectiveC)
// With an Objective-C runtime (decision 0023) `NSError` is an `NSObject`, as Foundation's is, so
// `@objc` members can take and hand back errors (a `(CustomerInfo?, NSError?) -> Void` completion).
// It describes itself through `NSObject`'s `description` (ObjectiveCBridging.swift).
open class NSError: NSObject, Error, @unchecked Sendable {
    public let domain: String
    public let code: Int
    public let userInfo: [String: Any]

    /// Required, so a generic `Result: NSError` can be made from its metatype, as an imported
    /// Objective-C class's initializer can (RevenueCat's `Error.addingUserInfo`).
    public required init(domain: String, code: Int, userInfo: [String: Any]? = nil) {
        self.domain = domain
        self.code = code
        self.userInfo = userInfo ?? [:]
        super.init()
    }
    /// An error with no domain, as `NSError()` makes on Apple platforms.
    public override convenience init() { self.init(domain: "", code: 0) }

    open var localizedDescription: String {
        if let text = userInfo[NSLocalizedDescriptionKey] as? String { return text }
        return "The operation couldn’t be completed. (\(domain) error \(code).)"
    }
    open var localizedFailureReason: String? { userInfo[NSLocalizedFailureReasonErrorKey] as? String }
    open var localizedRecoverySuggestion: String? { userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String }
    open override var description: String { localizedDescription }
    /// Equal to an error with the same domain, code and user info keys, as without the runtime.
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSError else { return false }
        return other === self || (other.domain == domain && other.code == code && Set(other.userInfo.keys) == Set(userInfo.keys))
    }
    open override var hash: Int { domain.hashValue ^ code }
}
#else
/// `Hashable` through `isEqual` and `hash`, as an `NSObject` is on Apple's platforms, so a value
/// that holds one can be `Equatable` (composable-core-location's `LocationManager.Error`).
open class NSError: Error, CustomStringConvertible, Hashable, @unchecked Sendable {
    public let domain: String
    public let code: Int
    public let userInfo: [String: Any]

    public init(domain: String, code: Int, userInfo: [String: Any]? = nil) {
        self.domain = domain
        self.code = code
        self.userInfo = userInfo ?? [:]
    }
    /// An error with no domain, as `NSError()` makes on Apple platforms (ButtonKit's previews
    /// throw one).
    public convenience init() { self.init(domain: "", code: 0) }

    open var localizedDescription: String {
        if let text = userInfo[NSLocalizedDescriptionKey] as? String { return text }
        return "The operation couldn’t be completed. (\(domain) error \(code).)"
    }
    open var localizedFailureReason: String? { userInfo[NSLocalizedFailureReasonErrorKey] as? String }
    open var localizedRecoverySuggestion: String? { userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String }
    public var description: String { localizedDescription }
    /// Equal to an error with the same domain, code and user info keys (OAuth2Error's `==` asks
    /// two wrapped errors `lhe.isEqual(rhe)`). Foundation also compares the user info values,
    /// which are `Any` here and have no equality to ask.
    open func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSError else { return false }
        return other === self || (other.domain == domain && other.code == code && Set(other.userInfo.keys) == Set(userInfo.keys))
    }
    open var hash: Int { domain.hashValue ^ code }
    public static func == (lhs: NSError, rhs: NSError) -> Bool { lhs.isEqual(rhs) }
    public func hash(into hasher: inout Hasher) { hasher.combine(hash) }
}
#endif

extension NSError {
    #if canImport(ObjectiveC)
    /// The keys of an error's user info. Under the Objective-C runtime it is `NSString`, as
    /// Foundation's is on Apple platforms, so an overload on `[NSError.UserInfoKey: Any]` and one
    /// on `[String: Any]` are two functions (RevenueCat's `Error.addingUserInfo`), and a key
    /// converts with `as String`.
    public typealias UserInfoKey = NSString
    #else
    /// The keys of an error's user info, which Swift spells as strings.
    public typealias UserInfoKey = String
    #endif
}

/// A specialized error that may be recoverable by presenting several potential recovery
/// options to the user.
public protocol RecoverableError: Error {
    /// The titles of the options a user can choose from to recover, in the order offered.
    var recoveryOptions: [String] { get }
    /// Attempts the recovery option at `recoveryOptionIndex`, reporting whether it succeeded.
    func attemptRecovery(optionIndex recoveryOptionIndex: Int, resultHandler handler: @escaping (_ recovered: Bool) -> Void)
    /// Attempts the recovery option at `recoveryOptionIndex` and answers whether it succeeded.
    func attemptRecovery(optionIndex recoveryOptionIndex: Int) -> Bool
}

extension RecoverableError {
    /// Attempts recovery synchronously and hands the result to the handler, as Foundation does.
    public func attemptRecovery(optionIndex recoveryOptionIndex: Int, resultHandler handler: @escaping (_ recovered: Bool) -> Void) {
        handler(attemptRecovery(optionIndex: recoveryOptionIndex))
    }
}

extension NSError {
    /// The titles of the error's recovery options, from its user info.
    public var localizedRecoveryOptions: [String]? { userInfo[NSLocalizedRecoveryOptionsErrorKey] as? [String] }
    /// The object that attempts recovery for the error, from its user info.
    public var recoveryAttempter: Any? { userInfo[NSRecoveryAttempterErrorKey] }
    /// The help anchor for the error, from its user info.
    public var helpAnchor: String? { userInfo[NSHelpAnchorErrorKey] as? String }

    /// Attempts a recovery option for `error`, as Foundation's error recovery attempter does:
    /// the error's own `RecoverableError` conformance, or that of the error's recovery
    /// attempter. Answers false when neither can recover.
    @discardableResult
    public static func attemptRecovery(fromError error: Error, optionIndex recoveryOptionIndex: Int) -> Bool {
        if let recoverable = error as? RecoverableError {
            return recoverable.attemptRecovery(optionIndex: recoveryOptionIndex)
        }
        if let attempter = (error as? NSError)?.recoveryAttempter as? RecoverableError {
            return attempter.attemptRecovery(optionIndex: recoveryOptionIndex)
        }
        return false
    }
}

#if canImport(ObjectiveC)
/// An error domain's name: `NSString` under the Objective-C runtime, as Foundation's is on Apple
/// platforms (RevenueCat's obsoleted `ErrorDomain: NSErrorDomain`).
public typealias NSErrorDomain = NSString
#else
/// An error domain's name, which Swift spells as a string.
public typealias NSErrorDomain = String
#endif

public let NSLocalizedDescriptionKey = "NSLocalizedDescription"
public let NSLocalizedFailureReasonErrorKey = "NSLocalizedFailureReason"
public let NSLocalizedRecoverySuggestionErrorKey = "NSLocalizedRecoverySuggestion"
public let NSUnderlyingErrorKey = "NSUnderlyingError"
public let NSCocoaErrorDomain = "NSCocoaErrorDomain"
public let NSURLErrorDomain = "NSURLErrorDomain"
public let NSPOSIXErrorDomain = "NSPOSIXErrorDomain"
public let NSOSStatusErrorDomain = "NSOSStatusErrorDomain"
/// Cocoa's error codes apps raise themselves (the Countries app's `Loadable`, decision 0021).
public let NSUserCancelledError = 3072
public let NSFileNoSuchFileError = 4
public let NSFileReadUnknownError = 256
public let NSFileReadNoPermissionError = 257
public let NSFileReadInvalidFileNameError = 258
public let NSFileReadCorruptFileError = 259
public let NSFileReadNoSuchFileError = 260
public let NSFileWriteUnknownError = 512
public let NSFileWriteNoPermissionError = 513
public let NSFileWriteFileExistsError = 516
public let NSFileWriteOutOfSpaceError = 640
public let NSURLErrorCancelled = -999
public let NSURLErrorNotConnectedToInternet = -1009
public let NSURLErrorTimedOut = -1001
public let NSURLErrorUnknown = -1
public let NSURLErrorBadURL = -1000
public let NSURLErrorUnsupportedURL = -1002
public let NSURLErrorCannotFindHost = -1003
public let NSURLErrorCannotConnectToHost = -1004
public let NSURLErrorNetworkConnectionLost = -1005
public let NSURLErrorDNSLookupFailed = -1006
public let NSURLErrorHTTPTooManyRedirects = -1007
public let NSURLErrorResourceUnavailable = -1008
public let NSURLErrorRedirectToNonExistentLocation = -1010
public let NSURLErrorBadServerResponse = -1011
public let NSURLErrorUserCancelledAuthentication = -1012
public let NSURLErrorUserAuthenticationRequired = -1013
public let NSURLErrorZeroByteResource = -1014
public let NSURLErrorCannotDecodeRawData = -1015
public let NSURLErrorCannotDecodeContentData = -1016
public let NSURLErrorCannotParseResponse = -1017
public let NSURLErrorInternationalRoamingOff = -1018
public let NSURLErrorCallIsActive = -1019
public let NSURLErrorDataNotAllowed = -1020
public let NSURLErrorSecureConnectionFailed = -1200
public let NSURLErrorCannotLoadFromNetwork = -2000
public let NSURLErrorFailingURLErrorKey = "NSErrorFailingURLKey"
public let NSURLErrorFailingURLStringErrorKey = "NSErrorFailingURLStringKey"
public let NSFilePathErrorKey = "NSFilePath"
public let NSHelpAnchorErrorKey = "NSHelpAnchor"
public let NSLocalizedRecoveryOptionsErrorKey = "NSLocalizedRecoveryOptions"
public let NSRecoveryAttempterErrorKey = "NSRecoveryAttempter"
public let NSDebugDescriptionErrorKey = "NSDebugDescription"
public let NSLocalizedFailureErrorKey = "NSLocalizedFailure"

/// A localized string from the main bundle: the string catalogs are not loaded in a page, so
/// `value` (when given and not empty) else the key, as `Bundle.localizedString` answers.
public func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = .main, value: String = "", comment: String) -> String {
    bundle.localizedString(forKey: key, value: value.isEmpty ? nil : value, table: tableName)
}

extension Error {
    /// Foundation's code for a Swift error: an `NSError`'s, else the case's position in its enum (1-based when it has none).
    public var _code: Int {
        if let error = self as? NSError { return error.code }
        if let raw = (self as? any RawRepresentable)?.rawValue as? Int { return raw }
        return 1
    }
    public var _domain: String { (self as? NSError)?.domain ?? String(reflecting: type(of: self)) }

    /// What Foundation's `localizedDescription` says for this error.
    public var localizedDescription: String {
        if let error = self as? NSError { return error.localizedDescription }
        if let error = self as? any LocalizedError, let text = error.errorDescription { return text }
        return "The operation couldn’t be completed. (\(String(reflecting: type(of: self))) error \(_code).)"
    }
}

/// Matches a Cocoa error's code against any error, as Foundation's `~=` for error codes does
/// (Bodega's `catch CocoaError.fileReadNoSuchFile`): a `CocoaError` with that code, or an
/// `NSError` in `NSCocoaErrorDomain` with it. The `CocoaError` is read by reflection, because
/// casting to it names its type metadata, which extracts CocoaError.swift and with it most of
/// FoundationEssentials, as `LocalizedError`'s descriptor would (4 MB of the Gallery).
public func ~= (code: CocoaError.Code, error: any Error) -> Bool {
    if let error = error as? NSError { return error.domain == NSCocoaErrorDomain && error.code == code.rawValue }
    let mirror = Mirror(reflecting: error)
    guard String(reflecting: mirror.subjectType).hasSuffix(".CocoaError") else { return false }
    for child in mirror.children where child.label == "code" {
        for field in Mirror(reflecting: child.value).children where field.label == "rawValue" {
            return field.value as? Int == code.rawValue
        }
    }
    return false
}
#endif
