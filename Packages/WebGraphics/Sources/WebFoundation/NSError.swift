// Foundation's `NSError` and `Error.localizedDescription` on wasm (decision 0021): there is
// no Objective-C bridge, so `NSError` is a plain error class with a domain, a code and a user
// info dictionary, and every error describes itself as Foundation's would: a `LocalizedError`
// by its `errorDescription`, an `NSError` by its user info, anything else by the operation
// sentence with its type and code.
#if os(WASI)
open class NSError: Error, CustomStringConvertible, @unchecked Sendable {
    public let domain: String
    public let code: Int
    public let userInfo: [String: Any]

    public init(domain: String, code: Int, userInfo: [String: Any]? = nil) {
        self.domain = domain
        self.code = code
        self.userInfo = userInfo ?? [:]
    }

    open var localizedDescription: String {
        if let text = userInfo[NSLocalizedDescriptionKey] as? String { return text }
        return "The operation couldn’t be completed. (\(domain) error \(code).)"
    }
    open var localizedFailureReason: String? { userInfo[NSLocalizedFailureReasonErrorKey] as? String }
    open var localizedRecoverySuggestion: String? { userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String }
    public var description: String { localizedDescription }
}

public let NSLocalizedDescriptionKey = "NSLocalizedDescription"
public let NSLocalizedFailureReasonErrorKey = "NSLocalizedFailureReason"
public let NSLocalizedRecoverySuggestionErrorKey = "NSLocalizedRecoverySuggestion"
public let NSUnderlyingErrorKey = "NSUnderlyingError"
public let NSCocoaErrorDomain = "NSCocoaErrorDomain"
public let NSURLErrorDomain = "NSURLErrorDomain"

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
#endif
