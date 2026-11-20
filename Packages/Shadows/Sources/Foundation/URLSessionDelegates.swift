// URLSession's delegate protocols with the Objective-C runtime (decision 0023): Foundation's
// own, `@objc` with optional methods, so a delegate answers only what it implements and code may
// ask whether it does (Nuke's DataLoader forwards `(delegate as? URLSessionTaskDelegate)?
// .urlSession?(…)` to the delegate it was handed). An `@objc` method may take an `Error`, a `URL`
// or `Data` only where the module named Foundation is loaded, so they are this module's, not
// WebFoundation's; WebFoundation holds the delegate as an object and calls it through
// `URLSession._delegateCalls`, which this module installs whenever a delegate is handed over.
// Without the runtime the protocols are WebFoundation's Swift ones (URLSessionDelegate.swift).
#if os(WASI) && canImport(ObjectiveC)
import ObjectiveC
import WebFoundation

/// What a session tells its delegate about the session itself.
@objc public protocol URLSessionDelegate: NSObjectProtocol {
    @objc optional func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?)
    @objc optional func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                                   completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
}

/// What a session tells its delegate about a task.
@objc public protocol URLSessionTaskDelegate: URLSessionDelegate {
    @objc optional func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                                   completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                                   newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                                   totalBytesExpectedToSend: Int64)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)
    @objc optional func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest,
                                   completionHandler: @escaping @Sendable (URLSession.DelayedRequestDisposition, URLRequest?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStreamFrom offset: Int64,
                                   completionHandler: @escaping @Sendable (InputStream?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didReceiveInformationalResponse response: HTTPURLResponse)
}

/// What a session tells its delegate about a data task's response and data.
@objc public protocol URLSessionDataDelegate: URLSessionTaskDelegate {
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                                   completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                                   completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask)
}

/// What a session tells its delegate about a download task.
@objc public protocol URLSessionDownloadDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
    @objc optional func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                   totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
    @objc optional func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64,
                                   expectedTotalBytes: Int64)
}

/// What a session tells its delegate about a WebSocket task (URLSessionWebSocketTask.swift).
@objc public protocol URLSessionWebSocketDelegate: URLSessionTaskDelegate {
    @objc optional func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?)
    @objc optional func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                   didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}


/// The calls WebFoundation's session makes, each with Foundation's answer for a method the
/// delegate leaves out: allow a response, and no body stream.
final class _URLSessionObjCDelegateCalls: _URLSessionDelegateCalls {
    static let shared = _URLSessionObjCDelegateCalls()

    func isTaskDelegate(_ delegate: AnyObject) -> Bool { delegate is any URLSessionTaskDelegate }
    func isDataDelegate(_ delegate: AnyObject) -> Bool { delegate is any URLSessionDataDelegate }
    func isDownloadDelegate(_ delegate: AnyObject) -> Bool { delegate is any URLSessionDownloadDelegate }
    func isWebSocketDelegate(_ delegate: AnyObject) -> Bool { delegate is any URLSessionWebSocketDelegate }

    func invalid(_ delegate: AnyObject, _ session: URLSession) {
        (delegate as? any URLSessionDelegate)?.urlSession?(session, didBecomeInvalidWithError: nil)
    }
    func created(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask) {
        (delegate as? any URLSessionTaskDelegate)?.urlSession?(session, didCreateTask: task)
    }
    func complete(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask, _ error: (any Error)?) {
        (delegate as? any URLSessionTaskDelegate)?.urlSession?(session, task: task, didCompleteWithError: error)
    }
    func sent(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask, _ sent: Int64, expected: Int64) {
        (delegate as? any URLSessionTaskDelegate)?.urlSession?(session, task: task, didSendBodyData: sent, totalBytesSent: sent,
                                                               totalBytesExpectedToSend: expected)
    }
    func bodyStream(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionTask, _ handler: @escaping @Sendable (InputStream?) -> Void) {
        if (delegate as? any URLSessionTaskDelegate)?.urlSession?(session, task: task, needNewBodyStream: handler) == nil { handler(nil) }
    }
    func response(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDataTask, _ response: URLResponse,
                  _ handler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        if (delegate as? any URLSessionDataDelegate)?.urlSession?(session, dataTask: task, didReceive: response, completionHandler: handler) == nil {
            handler(.allow)
        }
    }
    func data(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDataTask, _ data: Data) {
        (delegate as? any URLSessionDataDelegate)?.urlSession?(session, dataTask: task, didReceive: data)
    }
    func wrote(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDownloadTask, _ count: Int64) {
        (delegate as? any URLSessionDownloadDelegate)?.urlSession?(session, downloadTask: task, didWriteData: count,
                                                                   totalBytesWritten: count, totalBytesExpectedToWrite: count)
    }
    func finished(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionDownloadTask, _ file: URL) {
        (delegate as? any URLSessionDownloadDelegate)?.urlSession(session, downloadTask: task, didFinishDownloadingTo: file)
    }
    func opened(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionWebSocketTask, _ chosen: String?) {
        (delegate as? any URLSessionWebSocketDelegate)?.urlSession?(session, webSocketTask: task, didOpenWithProtocol: chosen)
    }
    func closed(_ delegate: AnyObject, _ session: URLSession, _ task: URLSessionWebSocketTask,
                _ code: URLSessionWebSocketTask.CloseCode, _ reason: Data?) {
        (delegate as? any URLSessionWebSocketDelegate)?.urlSession?(session, webSocketTask: task, didCloseWith: code, reason: reason)
    }
}

extension URLSession {
    /// A session that tells `delegate` what its tasks do, on `delegateQueue`.
    public convenience init(configuration: URLSessionConfiguration, delegate: (any URLSessionDelegate)?, delegateQueue queue: OperationQueue?) {
        if delegate != nil { URLSession._delegateCalls = _URLSessionObjCDelegateCalls.shared }
        self.init(configuration: configuration, _delegate: delegate, delegateQueue: queue)
    }

    /// The delegate, held until the session is invalidated, as Foundation holds it.
    public var delegate: (any URLSessionDelegate)? { _delegateObject as? any URLSessionDelegate }

    // The async forms that take a task delegate (iOS 15). The browser reports no progress while a
    // body goes out, so an upload tells its delegate once, when the body is sent; the others
    // accept one and fetch as the forms without it do.
    public func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
    public func data(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await data(from: url)
    }
    public func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
        try await download(for: request)
    }
    public func download(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
        try await download(from: url)
    }
    public func upload(for request: URLRequest, from bodyData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        if delegate != nil { URLSession._delegateCalls = _URLSessionObjCDelegateCalls.shared }
        return try await _upload(for: request, from: bodyData, telling: delegate)
    }
    public func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (AsyncBytes, URLResponse) {
        try await bytes(for: request)
    }
    public func bytes(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (AsyncBytes, URLResponse) {
        try await bytes(from: url)
    }
}
#endif
