// URLSession's delegate protocols and authentication types on wasm (decision 0021,
// pf-urlsession): Kingfisher and Alamofire fetch through a session delegate, an
// `NSObject` subclass conforming to `URLSessionDataDelegate`, and answer its authentication
// challenges. The browser does the fetch, so:
//
// - a data task made without a completion handler tells the delegate what came back, in
//   Foundation's order: the response (the delegate may cancel there), the data, then completion;
// - the browser checks the server's certificate and HTTP authentication itself, so a page never
//   sees a challenge: the challenge methods are never called, as on iOS for a server whose
//   certificate the system trusts and which asks for no credentials;
// - redirects are followed by the browser too, so `willPerformHTTPRedirection` isn't called.
//
// Apple's delegate methods are optional Objective-C requirements; here each has a default in a
// protocol extension that answers as Foundation does when the delegate doesn't implement it.
// The protocols refine `AnyObject`, not `NSObjectProtocol` (Threading.swift's `NSCacheDelegate`
// says why); delegates are `NSObject` subclasses either way.
#if os(WASI)

// MARK: - Authentication

public let NSURLAuthenticationMethodDefault = "NSURLAuthenticationMethodDefault"
public let NSURLAuthenticationMethodHTTPBasic = "NSURLAuthenticationMethodHTTPBasic"
public let NSURLAuthenticationMethodHTTPDigest = "NSURLAuthenticationMethodHTTPDigest"
public let NSURLAuthenticationMethodHTMLForm = "NSURLAuthenticationMethodHTMLForm"
public let NSURLAuthenticationMethodNTLM = "NSURLAuthenticationMethodNTLM"
public let NSURLAuthenticationMethodNegotiate = "NSURLAuthenticationMethodNegotiate"
public let NSURLAuthenticationMethodClientCertificate = "NSURLAuthenticationMethodClientCertificate"
public let NSURLAuthenticationMethodServerTrust = "NSURLAuthenticationMethodServerTrust"
public let NSURLProtectionSpaceHTTP = "http"
public let NSURLProtectionSpaceHTTPS = "https"

/// A server or an area on a server that requires authentication; equal to another for the same
/// host, port, protocol, realm and method, so it keys a credential store.
open class URLProtectionSpace: NSObject, @unchecked Sendable {
    public let host: String
    public let port: Int
    public let `protocol`: String?
    public let realm: String?
    public let authenticationMethod: String

    public init(host: String, port: Int, protocol: String?, realm: String?, authenticationMethod: String?) {
        self.host = host
        self.port = port
        self.`protocol` = `protocol`
        self.realm = realm
        self.authenticationMethod = authenticationMethod ?? NSURLAuthenticationMethodDefault
        super.init()
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? URLProtectionSpace else { return false }
        return host == other.host && port == other.port && `protocol` == other.protocol && realm == other.realm
            && authenticationMethod == other.authenticationMethod
    }

    open override var hash: Int {
        var hasher = Hasher()
        hasher.combine(host)
        hasher.combine(port)
        hasher.combine(realm)
        return hasher.finalize()
    }

    open var serverTrust: SecTrust? { nil }
    open var receivesCredentialSecurely: Bool { `protocol` == NSURLProtectionSpaceHTTPS }
    open var isProxy: Bool { false }
    open var proxyType: String? { nil }
    open var distinguishedNames: [Data]? { nil }
}

/// An authentication credential: a user name and password, or a server trust.
open class URLCredential: _WebObjectBase, @unchecked Sendable {
    public enum Persistence: UInt, Sendable {
        case none = 0, forSession = 1, permanent = 2, synchronizable = 3
    }

    public let user: String?
    public let password: String?
    public let persistence: Persistence

    public init(user: String, password: String, persistence: Persistence) {
        self.user = user
        self.password = password
        self.persistence = persistence
    }

    /// A credential that accepts a server's trust.
    public init(trust: SecTrust) {
        user = nil
        password = nil
        persistence = .forSession
    }

    open var hasPassword: Bool { password != nil }
    open var certificates: [Any] { [] }
}

/// Credentials kept per protection space. The browser answers HTTP authentication itself, so a
/// session never reads them; an app's own lookups find what it stored.
open class URLCredentialStorage: @unchecked Sendable {
    public static let shared = URLCredentialStorage()
    private var stored: [(space: URLProtectionSpace, credentials: [String: URLCredential], fallback: URLCredential?)] = []

    public init() {}

    private func index(of space: URLProtectionSpace) -> Int? {
        stored.firstIndex { $0.space.isEqual(space) }
    }

    open var allCredentials: [URLProtectionSpace: [String: URLCredential]] {
        var all: [URLProtectionSpace: [String: URLCredential]] = [:]
        for entry in stored { all[entry.space] = entry.credentials }
        return all
    }

    open func credentials(for space: URLProtectionSpace) -> [String: URLCredential]? {
        index(of: space).map { stored[$0].credentials }
    }

    open func set(_ credential: URLCredential, for space: URLProtectionSpace) {
        guard credential.persistence != .none, let user = credential.user else { return }
        if let index = index(of: space) { stored[index].credentials[user] = credential } else { stored.append((space, [user: credential], nil)) }
    }

    open func remove(_ credential: URLCredential, for space: URLProtectionSpace) {
        guard let index = index(of: space), let user = credential.user else { return }
        stored[index].credentials[user] = nil
        if stored[index].fallback?.user == user { stored[index].fallback = nil }
    }

    open func defaultCredential(for space: URLProtectionSpace) -> URLCredential? {
        index(of: space).flatMap { stored[$0].fallback }
    }

    open func setDefaultCredential(_ credential: URLCredential, for space: URLProtectionSpace) {
        set(credential, for: space)
        if let index = index(of: space) { stored[index].fallback = credential }
    }
}

/// What answers an authentication challenge (the older, sender-based API).
public protocol URLAuthenticationChallengeSender: AnyObject {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge)
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge)
    func cancel(_ challenge: URLAuthenticationChallenge)
}

/// A challenge from a server requiring authentication.
open class URLAuthenticationChallenge: _WebObjectBase, @unchecked Sendable {
    public let protectionSpace: URLProtectionSpace
    public let proposedCredential: URLCredential?
    public let previousFailureCount: Int
    public let failureResponse: URLResponse?
    public let error: (any Error)?
    public let sender: (any URLAuthenticationChallengeSender)?

    public init(protectionSpace space: URLProtectionSpace, proposedCredential credential: URLCredential?, previousFailureCount: Int,
                failureResponse response: URLResponse?, error: (any Error)?, sender: any URLAuthenticationChallengeSender) {
        protectionSpace = space
        proposedCredential = credential
        self.previousFailureCount = previousFailureCount
        failureResponse = response
        self.error = error
        self.sender = sender
    }
}

extension URLSession {
    // `@objc` with the runtime, as the delegate methods that take them are.
    #if canImport(ObjectiveC)
    /// How a delegate answers an authentication challenge.
    @objc public enum AuthChallengeDisposition: Int, Sendable {
        case useCredential = 0, performDefaultHandling = 1, cancelAuthenticationChallenge = 2, rejectProtectionSpace = 3
    }

    /// Whether a data task goes on after its response.
    @objc public enum ResponseDisposition: Int, Sendable {
        case cancel = 0, allow = 1, becomeDownload = 2, becomeStream = 3
    }

    /// How a delayed task goes on.
    @objc public enum DelayedRequestDisposition: Int, Sendable {
        case continueLoading = 0, useNewRequest = 1, cancel = 2
    }
    #else
    /// How a delegate answers an authentication challenge.
    public enum AuthChallengeDisposition: Int, Sendable {
        case useCredential = 0, performDefaultHandling = 1, cancelAuthenticationChallenge = 2, rejectProtectionSpace = 3
    }

    /// Whether a data task goes on after its response.
    public enum ResponseDisposition: Int, Sendable {
        case cancel = 0, allow = 1, becomeDownload = 2, becomeStream = 3
    }

    /// How a delayed task goes on.
    public enum DelayedRequestDisposition: Int, Sendable {
        case continueLoading = 0, useNewRequest = 1, cancel = 2
    }
    #endif
}

extension URLCache {
    /// Where a cached response may be kept.
    public enum StoragePolicy: UInt, Sendable { case allowed = 0, allowedInMemoryOnly = 1, notAllowed = 2 }
}

/// A response with its data, as a cache would keep it.
open class CachedURLResponse: _WebObjectBase, @unchecked Sendable {
    public let response: URLResponse
    public let data: Data
    public let userInfo: [AnyHashable: Any]?
    public let storagePolicy: URLCache.StoragePolicy

    public init(response: URLResponse, data: Data, userInfo: [AnyHashable: Any]? = nil, storagePolicy: URLCache.StoragePolicy = .allowed) {
        self.response = response
        self.data = data
        self.userInfo = userInfo
        self.storagePolicy = storagePolicy
    }
}

/// A task's timing, which the browser doesn't report: no transactions, and an interval that
/// spans the task's own life as far as the session saw it.
open class URLSessionTaskMetrics: _WebObjectBase, @unchecked Sendable {
    private let interval: DateInterval
    public override init() { interval = DateInterval(start: Date(), duration: 0) }
    open var taskInterval: DateInterval { interval }
    open var redirectCount: Int { 0 }
    open var transactionMetrics: [URLSessionTaskTransactionMetrics] { [] }
}

open class URLSessionTaskTransactionMetrics: _WebObjectBase, @unchecked Sendable {
    public override init() {}
}

// MARK: - Network status

/// Whether the browser is online, for SystemConfiguration's reachability. The host sets
/// `isOnline` (`navigator.onLine`) and calls `changed()` on the browser's online and offline
/// events; with no host the page counts as online.
public enum _WebNetworkStatus {
    nonisolated(unsafe) public static var isOnline: (() -> Bool)?
    nonisolated(unsafe) private static var observers: [Int: () -> Void] = [:]
    nonisolated(unsafe) private static var nextToken = 0

    public static var online: Bool { isOnline?() ?? true }

    /// Calls `handler` on each change until the token is passed to `removeObserver`.
    public static func addObserver(_ handler: @escaping () -> Void) -> Int {
        nextToken += 1
        observers[nextToken] = handler
        return nextToken
    }

    public static func removeObserver(_ token: Int) { observers[token] = nil }

    /// The host's report of an online or offline event.
    public static func changed() { for handler in observers.values { handler() } }
}

// MARK: - The delegate protocols

#if canImport(ObjectiveC)
// With the Objective-C runtime the protocols are Foundation's: `@objc`, every method optional but
// a download's file, so a delegate answers only what it implements and code may ask whether it
// does (Nuke's DataLoader forwards `(delegate as? URLSessionTaskDelegate)?.urlSession?(…)` to the
// delegate it was handed). An `@objc` method may take an `Error`, a `URL` or `Data` only where the
// module named Foundation is loaded, so the protocols are the Foundation module's
// (Packages/Shadows, URLSessionDelegates.swift). This module holds the delegate as an object and
// calls it through `_URLSessionDelegateCalls`, which that module installs when a delegate is
// handed to a session.

/// How the Foundation module calls a session's delegate: whether it plays each role, and each
/// event, with Foundation's answer for a method the delegate leaves out.
public protocol _URLSessionDelegateCalls: AnyObject, Sendable {
    func isTaskDelegate(_ delegate: AnyObject) -> Bool
    func isDataDelegate(_ delegate: AnyObject) -> Bool
    func isDownloadDelegate(_ delegate: AnyObject) -> Bool
    func isWebSocketDelegate(_ delegate: AnyObject) -> Bool
    func invalid(_ delegate: AnyObject, _ session: URLSession)
    func created(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask)
    func complete(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask, _ error: (any Error)?)
    func sent(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask, _ sent: Int64, expected: Int64)
    func bodyStream(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask, _ handler: @escaping @Sendable (InputStream?) -> Void)
    func response(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDataTask, _ response: URLResponse,
                  _ handler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void)
    func data(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDataTask, _ data: Data)
    func wrote(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDownloadTask, _ count: Int64)
    func finished(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDownloadTask, _ file: URL)
    func opened(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionWebSocketTask, _ chosen: String?)
    func closed(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionWebSocketTask,
                _ code: URLSessionWebSocketTask.CloseCode, _ reason: Data?)
}

extension URLSession {
    /// The Foundation module's calls, installed before it hands a session a delegate.
    nonisolated(unsafe) public static var _delegateCalls: (any _URLSessionDelegateCalls)?
}

public typealias _SessionDelegate = AnyObject
public typealias _TaskDelegate = AnyObject
public typealias _DataDelegate = AnyObject
public typealias _DownloadDelegate = AnyObject
public typealias _WebSocketDelegate = AnyObject

#else
/// What a session tells its delegate about the session itself.
public protocol URLSessionDelegate: AnyObject {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?)
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
}

extension URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {}
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}

/// What a session tells its delegate about a task.
public protocol URLSessionTaskDelegate: URLSessionDelegate {
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask)
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64)
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void)
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask)
    func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLSession.DelayedRequestDisposition, URLRequest?) -> Void)
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStreamFrom offset: Int64,
                    completionHandler: @escaping @Sendable (InputStream?) -> Void)
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceiveInformationalResponse response: HTTPURLResponse)
}

extension URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {}
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {}
    public func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void) {
        completionHandler(nil)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {}
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {}
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {}
    public func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest,
                           completionHandler: @escaping @Sendable (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
        completionHandler(.continueLoading, nil)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStreamFrom offset: Int64,
                           completionHandler: @escaping @Sendable (InputStream?) -> Void) {
        completionHandler(nil)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceiveInformationalResponse response: HTTPURLResponse) {}
}

/// What a session tells its delegate about a data task's response and data.
public protocol URLSessionDataDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void)
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                    completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void)
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask)
}

extension URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {}
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {}
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                           completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void) {
        completionHandler(proposedResponse)
    }
}

/// What a session tells its delegate about a download task.
public protocol URLSessionDownloadDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64,
                    expectedTotalBytes: Int64)
}

extension URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {}
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64,
                           expectedTotalBytes: Int64) {}
}

/// What a session tells its delegate about a WebSocket task (URLSessionWebSocketTask.swift).
public protocol URLSessionWebSocketDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?)
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?)
}

extension URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {}
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?) {}
}

public typealias _SessionDelegate = any URLSessionDelegate
public typealias _TaskDelegate = any URLSessionTaskDelegate
public typealias _DataDelegate = any URLSessionDataDelegate
public typealias _DownloadDelegate = any URLSessionDownloadDelegate
public typealias _WebSocketDelegate = any URLSessionWebSocketDelegate

#endif

// The session's calls to its delegate. Without the runtime they are the Swift protocols' own
// methods; with it they go through the Foundation module's calls, and a delegate that the module
// never installed calls for (none can be handed over without it) hears nothing, with Foundation's
// answer for what asks.
extension URLSession {
    #if canImport(ObjectiveC)
    func _asTask(_ delegate: _SessionDelegate?) -> _TaskDelegate? {
        delegate.flatMap { Self._delegateCalls?.isTaskDelegate($0) == true ? $0 : nil }
    }
    func _asData(_ delegate: _SessionDelegate?) -> _DataDelegate? {
        delegate.flatMap { Self._delegateCalls?.isDataDelegate($0) == true ? $0 : nil }
    }
    func _asDownload(_ delegate: _SessionDelegate?) -> _DownloadDelegate? {
        delegate.flatMap { Self._delegateCalls?.isDownloadDelegate($0) == true ? $0 : nil }
    }
    func _asWebSocket(_ delegate: _SessionDelegate?) -> _WebSocketDelegate? {
        delegate.flatMap { Self._delegateCalls?.isWebSocketDelegate($0) == true ? $0 : nil }
    }
    func _tellInvalid(_ delegate: _SessionDelegate) { Self._delegateCalls?.invalid(delegate, self) }
    func _tellCreated(_ task: URLSessionTask) {
        if let delegate = _asTask(_delegate) { Self._delegateCalls?.created(delegate, self, task) }
    }
    func _tellComplete(_ delegate: _TaskDelegate, _ task: URLSessionTask, _ error: (any Error)?) {
        Self._delegateCalls?.complete(delegate, self, task, error)
    }
    func _tellSent(_ delegate: _TaskDelegate, _ task: URLSessionTask, _ sent: Int64, expected: Int64) {
        Self._delegateCalls?.sent(delegate, self, task, sent, expected: expected)
    }
    func _askBodyStream(_ delegate: _TaskDelegate, _ task: URLSessionTask, _ handler: @escaping @Sendable (InputStream?) -> Void) {
        guard let calls = Self._delegateCalls else { return handler(nil) }
        calls.bodyStream(delegate, self, task, handler)
    }
    func _askResponse(_ delegate: _DataDelegate, _ task: URLSessionDataTask, _ response: URLResponse,
                      _ handler: @escaping @Sendable (ResponseDisposition) -> Void) {
        guard let calls = Self._delegateCalls else { return handler(.allow) }
        calls.response(delegate, self, task, response, handler)
    }
    func _tellData(_ delegate: _DataDelegate, _ task: URLSessionDataTask, _ data: Data) {
        Self._delegateCalls?.data(delegate, self, task, data)
    }
    func _tellWrote(_ delegate: _DownloadDelegate, _ task: URLSessionDownloadTask, _ count: Int64) {
        Self._delegateCalls?.wrote(delegate, self, task, count)
    }
    func _tellFinished(_ delegate: _DownloadDelegate, _ task: URLSessionDownloadTask, _ file: URL) {
        Self._delegateCalls?.finished(delegate, self, task, file)
    }
    func _tellOpened(_ delegate: _WebSocketDelegate, _ task: URLSessionWebSocketTask, _ chosen: String?) {
        Self._delegateCalls?.opened(delegate, self, task, chosen)
    }
    func _tellClosed(_ delegate: _WebSocketDelegate, _ task: URLSessionWebSocketTask,
                     _ code: URLSessionWebSocketTask.CloseCode, _ reason: Data?) {
        Self._delegateCalls?.closed(delegate, self, task, code, reason)
    }
    #else
    func _asTask(_ delegate: _SessionDelegate?) -> _TaskDelegate? { delegate as? any URLSessionTaskDelegate }
    func _asData(_ delegate: _SessionDelegate?) -> _DataDelegate? { delegate as? any URLSessionDataDelegate }
    func _asDownload(_ delegate: _SessionDelegate?) -> _DownloadDelegate? { delegate as? any URLSessionDownloadDelegate }
    func _asWebSocket(_ delegate: _SessionDelegate?) -> _WebSocketDelegate? { delegate as? any URLSessionWebSocketDelegate }
    func _tellInvalid(_ delegate: _SessionDelegate) { delegate.urlSession(self, didBecomeInvalidWithError: nil) }
    func _tellCreated(_ task: URLSessionTask) { _asTask(_delegate)?.urlSession(self, didCreateTask: task) }
    func _tellComplete(_ delegate: _TaskDelegate, _ task: URLSessionTask, _ error: (any Error)?) {
        delegate.urlSession(self, task: task, didCompleteWithError: error)
    }
    func _tellSent(_ delegate: _TaskDelegate, _ task: URLSessionTask, _ sent: Int64, expected: Int64) {
        delegate.urlSession(self, task: task, didSendBodyData: sent, totalBytesSent: sent, totalBytesExpectedToSend: expected)
    }
    func _askBodyStream(_ delegate: _TaskDelegate, _ task: URLSessionTask, _ handler: @escaping @Sendable (InputStream?) -> Void) {
        delegate.urlSession(self, task: task, needNewBodyStream: handler)
    }
    func _askResponse(_ delegate: _DataDelegate, _ task: URLSessionDataTask, _ response: URLResponse,
                      _ handler: @escaping @Sendable (ResponseDisposition) -> Void) {
        delegate.urlSession(self, dataTask: task, didReceive: response, completionHandler: handler)
    }
    func _tellData(_ delegate: _DataDelegate, _ task: URLSessionDataTask, _ data: Data) {
        delegate.urlSession(self, dataTask: task, didReceive: data)
    }
    func _tellWrote(_ delegate: _DownloadDelegate, _ task: URLSessionDownloadTask, _ count: Int64) {
        delegate.urlSession(self, downloadTask: task, didWriteData: count, totalBytesWritten: count, totalBytesExpectedToWrite: count)
    }
    func _tellFinished(_ delegate: _DownloadDelegate, _ task: URLSessionDownloadTask, _ file: URL) {
        delegate.urlSession(self, downloadTask: task, didFinishDownloadingTo: file)
    }
    func _tellOpened(_ delegate: _WebSocketDelegate, _ task: URLSessionWebSocketTask, _ chosen: String?) {
        delegate.urlSession(self, webSocketTask: task, didOpenWithProtocol: chosen)
    }
    func _tellClosed(_ delegate: _WebSocketDelegate, _ task: URLSessionWebSocketTask,
                     _ code: URLSessionWebSocketTask.CloseCode, _ reason: Data?) {
        delegate.urlSession(self, webSocketTask: task, didCloseWith: code, reason: reason)
    }
    #endif
}

// MARK: - Delivery

extension URLSession {
    /// A data task whose outcome goes to the session's delegate (Foundation's `dataTask(with:)`
    /// without a completion handler).
    func delegatedTask(_ request: URLRequest) -> URLSessionDataTask {
        delegated(request, as: URLSessionDataTask.init(identifier:request:start:)) { [self] task, data, response, error in
            deliver(task, data: data, response: response, error: error)
        }
    }

    /// A task whose outcome goes to `report` once the task has been handed back: a request that
    /// fails before it is sent (a bad URL) reports on the next turn.
    private func delegated<Kind: URLSessionTask>(_ request: URLRequest,
                                                 as make: (Int, URLRequest, @escaping @Sendable () -> _WebURLSession.Task) -> Kind,
                                                 failure: URLError? = nil, body: (@Sendable (Kind) -> Data?)? = nil,
                                                 report: @escaping @Sendable (Kind, Data?, URLResponse?, (any Error)?) -> Void) -> Kind {
        let made = _Box<Kind?>(nil)
        let task = makeTask(request, as: make, failure: failure, body: body) { data, response, error in
            if let task = made.value {
                report(task, data, response, error)
            } else {
                DispatchQueue.main.async {
                    if let task = made.value { report(task, data, response, error) }
                }
            }
        }
        made.value = task
        return task
    }

    /// A download whose body the delegate gets as a file: the bytes written, the file (removed
    /// once the delegate returns, as Foundation removes it), then completion.
    func delegatedDownload(_ request: URLRequest, failure: URLError? = nil) -> URLSessionDownloadTask {
        delegated(request, as: URLSessionDownloadTask.init(identifier:request:start:), failure: failure) { [self] task, data, response, error in
            guard let delegate = _asTask(_delegate) else { return }
            if let data, response != nil, let downloads = _asDownload(delegate) {
                let count = Int64(data.count)
                _tellWrote(downloads, task, count)
                do {
                    let file = try Self.temporaryDownload(data)
                    _tellFinished(downloads, task, file)
                    try? FileManager.default.removeItem(at: file)
                } catch {
                    _tellComplete(delegate, task, error)
                    return
                }
            }
            _tellComplete(delegate, task, error)
        }
    }

    /// An upload that tells the delegate its body went out, then reports as a data task does.
    func delegatedUpload(_ request: URLRequest, bodyCount: Int, failure: URLError? = nil) -> URLSessionUploadTask {
        delegated(request, as: URLSessionUploadTask.init(identifier:request:start:), failure: failure) { [self] task, data, response, error in
            if response != nil, let delegate = _asTask(_delegate) {
                let sent = Int64(bodyCount)
                _tellSent(delegate, task, sent, expected: sent)
            }
            deliver(task, data: data, response: response, error: error)
        }
    }

    /// An upload whose body the delegate hands over as a stream when the task starts.
    func streamedUpload(_ request: URLRequest) -> URLSessionUploadTask {
        let counted = _Box(0)
        let uploading = Self.uploading(request, nil)
        return delegated(uploading, as: URLSessionUploadTask.init(identifier:request:start:), body: { [self] task in
            guard let delegate = _asTask(_delegate) else { return nil }
            let stream = _Box<InputStream?>(nil)
            _askBodyStream(delegate, task) { stream.value = $0 }
            guard let body = stream.value.map(Self.readAll) else { return nil }
            counted.value = body.count
            return body
        }) { [self] task, data, response, error in
            if response != nil, let delegate = _asTask(_delegate) {
                let sent = Int64(counted.value)
                _tellSent(delegate, task, sent, expected: NSURLSessionTransferSizeUnknown)
            }
            deliver(task, data: data, response: response, error: error)
        }
    }

    /// Every byte left in `stream`.
    static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            body.append(contentsOf: buffer[0..<count])
        }
        return body
    }

    /// Tells the delegate what a task received: the response (where the delegate may cancel),
    /// the data, then completion; or the failure.
    fileprivate func deliver(_ task: URLSessionDataTask, data: Data?, response: URLResponse?, error: (any Error)?) {
        guard let delegate = _asTask(_delegate) else { return }
        guard let response, let dataDelegate = _asData(delegate) else {
            _tellComplete(delegate, task, error)
            return
        }
        _askResponse(dataDelegate, task, response) { [self] disposition in
            guard let dataDelegate = self._asData(self._delegate) else { return }
            if disposition == .cancel {
                let cancelled = URLError(.cancelled)
                task.finished(response: response, error: cancelled)
                _tellComplete(dataDelegate, task, cancelled)
                return
            }
            if let data, !data.isEmpty { _tellData(dataDelegate, task, data) }
            _tellComplete(dataDelegate, task, nil)
        }
    }
}
#endif
