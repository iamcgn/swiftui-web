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
open class URLCredential: @unchecked Sendable {
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
open class URLAuthenticationChallenge: @unchecked Sendable {
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
}

extension URLCache {
    /// Where a cached response may be kept.
    public enum StoragePolicy: UInt, Sendable { case allowed = 0, allowedInMemoryOnly = 1, notAllowed = 2 }
}

/// A response with its data, as a cache would keep it.
open class CachedURLResponse: @unchecked Sendable {
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
open class URLSessionTaskMetrics: @unchecked Sendable {
    private let interval: DateInterval
    public init() { interval = DateInterval(start: Date(), duration: 0) }
    open var taskInterval: DateInterval { interval }
    open var redirectCount: Int { 0 }
    open var transactionMetrics: [URLSessionTaskTransactionMetrics] { [] }
}

open class URLSessionTaskTransactionMetrics: @unchecked Sendable {
    public init() {}
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
}

extension URLSessionTaskDelegate {
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
}

/// What a session tells its delegate about a data task's response and data.
public protocol URLSessionDataDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void)
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                    completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void)
}

extension URLSessionDataDelegate {
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
            guard let delegate = delegate as? any URLSessionTaskDelegate else { return }
            if let data, response != nil, let downloads = delegate as? any URLSessionDownloadDelegate {
                let count = Int64(data.count)
                downloads.urlSession(self, downloadTask: task, didWriteData: count, totalBytesWritten: count, totalBytesExpectedToWrite: count)
                do {
                    let file = try Self.temporaryDownload(data)
                    downloads.urlSession(self, downloadTask: task, didFinishDownloadingTo: file)
                    try? FileManager.default.removeItem(at: file)
                } catch {
                    delegate.urlSession(self, task: task, didCompleteWithError: error)
                    return
                }
            }
            delegate.urlSession(self, task: task, didCompleteWithError: error)
        }
    }

    /// An upload that tells the delegate its body went out, then reports as a data task does.
    func delegatedUpload(_ request: URLRequest, bodyCount: Int, failure: URLError? = nil) -> URLSessionUploadTask {
        delegated(request, as: URLSessionUploadTask.init(identifier:request:start:), failure: failure) { [self] task, data, response, error in
            if response != nil, let delegate = delegate as? any URLSessionTaskDelegate {
                let sent = Int64(bodyCount)
                delegate.urlSession(self, task: task, didSendBodyData: sent, totalBytesSent: sent, totalBytesExpectedToSend: sent)
            }
            deliver(task, data: data, response: response, error: error)
        }
    }

    /// An upload whose body the delegate hands over as a stream when the task starts.
    func streamedUpload(_ request: URLRequest) -> URLSessionUploadTask {
        let counted = _Box(0)
        let uploading = Self.uploading(request, nil)
        return delegated(uploading, as: URLSessionUploadTask.init(identifier:request:start:), body: { [self] task in
            guard let delegate = delegate as? any URLSessionTaskDelegate else { return nil }
            let stream = _Box<InputStream?>(nil)
            delegate.urlSession(self, task: task, needNewBodyStream: { stream.value = $0 })
            guard let body = stream.value.map(Self.readAll) else { return nil }
            counted.value = body.count
            return body
        }) { [self] task, data, response, error in
            if response != nil, let delegate = delegate as? any URLSessionTaskDelegate {
                let sent = Int64(counted.value)
                delegate.urlSession(self, task: task, didSendBodyData: sent, totalBytesSent: sent, totalBytesExpectedToSend: NSURLSessionTransferSizeUnknown)
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
        guard let delegate = delegate as? any URLSessionTaskDelegate else { return }
        guard let response, let dataDelegate = delegate as? any URLSessionDataDelegate else {
            delegate.urlSession(self, task: task, didCompleteWithError: error)
            return
        }
        dataDelegate.urlSession(self, dataTask: task, didReceive: response) { [self] disposition in
            guard let dataDelegate = self.delegate as? any URLSessionDataDelegate else { return }
            if disposition == .cancel {
                let cancelled = URLError(.cancelled)
                task.finished(response: response, error: cancelled)
                dataDelegate.urlSession(self, task: task, didCompleteWithError: cancelled)
                return
            }
            if let data, !data.isEmpty { dataDelegate.urlSession(self, dataTask: task, didReceive: data) }
            dataDelegate.urlSession(self, task: task, didCompleteWithError: nil)
        }
    }
}
#endif
