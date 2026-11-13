// URLSession over the host's fetch (decision 0021, pf-urlsession). The core (`_WebURLSession`)
// is platform-independent and tested against a fake host; on wasm the public `URLSession`,
// `URLRequest`, `URLResponse`, `HTTPURLResponse`, `URLError` and `URLSessionConfiguration`
// wrap it (Apple's Foundation has them elsewhere). The semantics an app relies on:
//
// - an HTTP error status is a *response* (`HTTPURLResponse.statusCode`, the body as data), as
//   `URLSession.data(for:)` answers on iOS — the app decides what 404 means;
// - a transport failure — the host unreachable, a CORS refusal (the browser hides the response
//   entirely), a timeout, a cancelled task — is a thrown `URLError` with its code, and nothing
//   else: the two are never confused;
// - method, headers and body go to the host as written; the response's status, headers and
//   bytes come back as the host read them.
//
// The browser host is `fetch` (SwiftUIWebCanvas/NetworkHost.swift): CORS is the browser's,
// a refused cross-origin request fails as a transport error, and a redirect is followed by
// the browser (the final response is what comes back).

// MARK: - The host

/// A request as the host sends it.
public struct _WebHTTPRequest: Sendable {
    public var url: String
    public var method: String
    public var headers: [String: String]
    public var body: [UInt8]?
    public var timeout: Double
    public init(url: String, method: String, headers: [String: String], body: [UInt8]?, timeout: Double) {
        self.url = url; self.method = method; self.headers = headers; self.body = body; self.timeout = timeout
    }
}

/// What the host read: the final URL, status, headers and bytes.
public struct _WebHTTPResponse: Sendable {
    public var url: String
    public var status: Int
    public var headers: [String: String]
    public var body: [UInt8]
    public init(url: String, status: Int, headers: [String: String], body: [UInt8]) {
        self.url = url; self.status = status; self.headers = headers; self.body = body
    }
}

/// Why the host could not read a response at all.
public enum _WebHTTPFailure: Error, Sendable, Equatable {
    case cancelled
    case timedOut
    case badURL
    case unreachable(String)      // the browser's TypeError: a refused CORS request, DNS, a dropped connection
    case notConnected
}

/// A request in flight at the host; cancelling it ends it with `.cancelled`.
public protocol _WebHTTPTask: AnyObject {
    func cancel()
}

/// The host hook: sends a request, answers once with a response or a failure.
public enum _WebHTTPHost {
    nonisolated(unsafe) public static var send: ((_WebHTTPRequest, @escaping @Sendable (Result<_WebHTTPResponse, _WebHTTPFailure>) -> Void) -> (any _WebHTTPTask)?)?
}

// MARK: - The core

/// The session core: the configuration applied to each request, the task bookkeeping, the
/// mapping of the host's answer onto a response or an error.
public final class _WebURLSession: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var timeoutIntervalForRequest: Double = 60
        public var timeoutIntervalForResource: Double = 7 * 24 * 3600
        public var httpAdditionalHeaders: [String: String] = [:]
        public var allowsCellularAccess = true
        public var waitsForConnectivity = false
        public var httpMaximumConnectionsPerHost = 6
        public var httpShouldSetCookies = true
        public init() {}
    }

    public enum Outcome: Sendable {
        case response(_WebHTTPResponse)
        case failure(_WebHTTPFailure)
    }

    /// One task: the host's handle, and whether it already answered.
    public final class Task: @unchecked Sendable {
        public let identifier: Int
        public private(set) var isCancelled = false
        public private(set) var isFinished = false
        fileprivate var hostTask: (any _WebHTTPTask)?
        fileprivate let completion: @Sendable (Outcome) -> Void
        init(identifier: Int, completion: @escaping @Sendable (Outcome) -> Void) {
            self.identifier = identifier
            self.completion = completion
        }
        /// Cancels: the host task is told, and the task answers `.cancelled` once (either here
        /// or when the host reports it, whichever is first).
        public func cancel() {
            guard !isFinished, !isCancelled else { return }
            isCancelled = true
            hostTask?.cancel()
            finish(.failure(.cancelled))
        }
        fileprivate func finish(_ outcome: Outcome) {
            guard !isFinished else { return }
            isFinished = true
            completion(outcome)
        }
    }

    public let configuration: Configuration
    private var nextIdentifier = 1
    public private(set) var tasks: [Task] = []

    public init(configuration: Configuration = Configuration()) { self.configuration = configuration }

    /// Sends `request` through the host; `completion` gets the host's response (any status)
    /// or the failure, exactly once. Without a host every request is `.unreachable`.
    @discardableResult
    public func send(url: String, method: String?, headers: [String: String]?, body: [UInt8]?, timeout: Double?,
                     completion: @escaping @Sendable (Outcome) -> Void) -> Task {
        let task = Task(identifier: nextIdentifier, completion: completion)
        nextIdentifier += 1
        tasks.append(task)
        var merged = configuration.httpAdditionalHeaders
        for (key, value) in headers ?? [:] { merged[key] = value }
        let request = _WebHTTPRequest(url: url, method: (method ?? "GET").uppercased(), headers: merged, body: body,
                                      timeout: timeout ?? configuration.timeoutIntervalForRequest)
        guard let send = _WebHTTPHost.send else {
            task.finish(.failure(.unreachable("no network host")))
            return task
        }
        task.hostTask = send(request) { result in
            switch result {
            case .success(let response): task.finish(.response(response))
            case .failure(let failure): task.finish(.failure(failure))
            }
        }
        return task
    }

    /// Ends every task in flight with `.cancelled`.
    public func cancelAll() { for task in tasks where !task.isFinished { task.cancel() } }
}

#if os(WASI)

// MARK: - The public API on wasm

/// A URL load request that is independent of protocol or URL scheme.
public struct URLRequest: Hashable, Sendable {
    public enum CachePolicy: UInt, Sendable {
        case useProtocolCachePolicy = 0
        case reloadIgnoringLocalCacheData = 1
        case reloadIgnoringLocalAndRemoteCacheData = 4
        case returnCacheDataElseLoad = 2
        case returnCacheDataDontLoad = 3
        case reloadRevalidatingCacheData = 5
    }
    public enum NetworkServiceType: UInt, Sendable { case `default` = 0, voip = 1, video = 2, background = 3, voice = 4, responsiveData = 6, avStreaming = 8, responsiveAV = 9, callSignaling = 11 }

    public var url: URL?
    public var cachePolicy: CachePolicy
    public var timeoutInterval: TimeInterval
    public var httpMethod: String? = "GET"
    public var allHTTPHeaderFields: [String: String]?
    public var httpBody: Data?
    public var allowsCellularAccess = true
    public var httpShouldHandleCookies = true
    public var networkServiceType: NetworkServiceType = .default
    public var mainDocumentURL: URL?
    public var httpShouldUsePipelining = false
    public var allowsConstrainedNetworkAccess = true
    public var allowsExpensiveNetworkAccess = true

    public init(url: URL, cachePolicy: CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60) {
        self.url = url
        self.cachePolicy = cachePolicy
        self.timeoutInterval = timeoutInterval
    }

    public func value(forHTTPHeaderField field: String) -> String? {
        allHTTPHeaderFields?.first { $0.key.lowercased() == field.lowercased() }?.value
    }
    public mutating func setValue(_ value: String?, forHTTPHeaderField field: String) {
        var fields = allHTTPHeaderFields ?? [:]
        for key in fields.keys where key.lowercased() == field.lowercased() { fields[key] = nil }
        if let value { fields[field] = value }
        allHTTPHeaderFields = fields.isEmpty ? nil : fields
    }
    public mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
        if let existing = self.value(forHTTPHeaderField: field) { setValue(existing + "," + value, forHTTPHeaderField: field) } else { setValue(value, forHTTPHeaderField: field) }
    }
}

/// The metadata associated with the response to a URL load request.
open class URLResponse: @unchecked Sendable {
    public let url: URL?
    public let mimeType: String?
    public let expectedContentLength: Int64
    public let textEncodingName: String?
    public init(url: URL, mimeType: String?, expectedContentLength: Int, textEncodingName: String?) {
        self.url = url
        self.mimeType = mimeType
        self.expectedContentLength = Int64(expectedContentLength)
        self.textEncodingName = textEncodingName
    }
    public var suggestedFilename: String? { url?.lastPathComponent }
}

/// The metadata associated with the response to an HTTP protocol URL load request.
public final class HTTPURLResponse: URLResponse, @unchecked Sendable {
    public let statusCode: Int
    public let allHeaderFields: [AnyHashable: Any]
    private let headerFields: [String: String]

    public init?(url: URL, statusCode: Int, httpVersion: String?, headerFields: [String: String]?) {
        self.statusCode = statusCode
        self.headerFields = headerFields ?? [:]
        var all: [AnyHashable: Any] = [:]
        for (key, value) in headerFields ?? [:] { all[key] = value }
        allHeaderFields = all
        let contentType = headerFields?.first { $0.key.lowercased() == "content-type" }?.value
        let lengthField = headerFields?.first { $0.key.lowercased() == "content-length" }?.value
        let length = lengthField.flatMap { Int($0) } ?? -1
        // The media type before any parameter ("application/json; charset=utf-8"), trimmed.
        let mime = contentType.map { String($0.prefix { $0 != ";" }) }.map { value -> String in
            var scalars = Substring(value)
            while scalars.first == " " { scalars = scalars.dropFirst() }
            while scalars.last == " " { scalars = scalars.dropLast() }
            return String(scalars)
        }
        super.init(url: url, mimeType: mime, expectedContentLength: length, textEncodingName: nil)
    }

    /// A header's value, case-insensitively as HTTP headers are.
    public func value(forHTTPHeaderField field: String) -> String? {
        headerFields.first { $0.key.lowercased() == field.lowercased() }?.value
    }

    public class func localizedString(forStatusCode statusCode: Int) -> String {
        switch statusCode {
        case 200: "no error"
        case 201: "created"
        case 204: "no content"
        case 301: "moved permanently"
        case 304: "not modified"
        case 400: "bad request"
        case 401: "unauthorized"
        case 403: "forbidden"
        case 404: "not found"
        case 429: "too many requests"
        case 500: "internal server error"
        case 502: "bad gateway"
        case 503: "service unavailable"
        default: statusCode < 400 ? "no error" : "server error"
        }
    }
}

/// An error that occurs during URL loading.
public struct URLError: Error, Hashable, @unchecked Sendable, CustomStringConvertible, LocalizedError {
    public struct Code: RawRepresentable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let unknown = Code(rawValue: -1)
        public static let cancelled = Code(rawValue: -999)
        public static let badURL = Code(rawValue: -1000)
        public static let timedOut = Code(rawValue: -1001)
        public static let unsupportedURL = Code(rawValue: -1002)
        public static let cannotFindHost = Code(rawValue: -1003)
        public static let cannotConnectToHost = Code(rawValue: -1004)
        public static let networkConnectionLost = Code(rawValue: -1005)
        public static let resourceUnavailable = Code(rawValue: -1008)
        public static let notConnectedToInternet = Code(rawValue: -1009)
        public static let badServerResponse = Code(rawValue: -1011)
        public static let userCancelledAuthentication = Code(rawValue: -1012)
        public static let cannotDecodeRawData = Code(rawValue: -1015)
        public static let cannotParseResponse = Code(rawValue: -1017)
        public static let secureConnectionFailed = Code(rawValue: -1200)
        // The rest of Foundation's codes, which the browser's fetch never reports; computed, so an
        // app that never names them does not ship them.
        public static var backgroundSessionRequiresSharedContainer: Code { Code(rawValue: -995) }
        public static var backgroundSessionInUseByAnotherProcess: Code { Code(rawValue: -996) }
        public static var backgroundSessionWasDisconnected: Code { Code(rawValue: -997) }
        public static var dnsLookupFailed: Code { Code(rawValue: -1006) }
        public static var httpTooManyRedirects: Code { Code(rawValue: -1007) }
        public static var redirectToNonExistentLocation: Code { Code(rawValue: -1010) }
        public static var userAuthenticationRequired: Code { Code(rawValue: -1013) }
        public static var zeroByteResource: Code { Code(rawValue: -1014) }
        public static var cannotDecodeContentData: Code { Code(rawValue: -1016) }
        public static var internationalRoamingOff: Code { Code(rawValue: -1018) }
        public static var callIsActive: Code { Code(rawValue: -1019) }
        public static var dataNotAllowed: Code { Code(rawValue: -1020) }
        public static var requestBodyStreamExhausted: Code { Code(rawValue: -1021) }
        public static var appTransportSecurityRequiresSecureConnection: Code { Code(rawValue: -1022) }
        public static var fileDoesNotExist: Code { Code(rawValue: -1100) }
        public static var fileIsDirectory: Code { Code(rawValue: -1101) }
        public static var noPermissionsToReadFile: Code { Code(rawValue: -1102) }
        public static var dataLengthExceedsMaximum: Code { Code(rawValue: -1103) }
        public static var fileOutsideSafeArea: Code { Code(rawValue: -1104) }
        public static var serverCertificateHasBadDate: Code { Code(rawValue: -1201) }
        public static var serverCertificateUntrusted: Code { Code(rawValue: -1202) }
        public static var serverCertificateHasUnknownRoot: Code { Code(rawValue: -1203) }
        public static var serverCertificateNotYetValid: Code { Code(rawValue: -1204) }
        public static var clientCertificateRejected: Code { Code(rawValue: -1205) }
        public static var clientCertificateRequired: Code { Code(rawValue: -1206) }
        public static var cannotLoadFromNetwork: Code { Code(rawValue: -2000) }
        public static var cannotCreateFile: Code { Code(rawValue: -3000) }
        public static var cannotOpenFile: Code { Code(rawValue: -3001) }
        public static var cannotCloseFile: Code { Code(rawValue: -3002) }
        public static var cannotWriteToFile: Code { Code(rawValue: -3003) }
        public static var cannotRemoveFile: Code { Code(rawValue: -3004) }
        public static var cannotMoveFile: Code { Code(rawValue: -3005) }
        public static var downloadDecodingFailedMidStream: Code { Code(rawValue: -3006) }
        public static var downloadDecodingFailedToComplete: Code { Code(rawValue: -3007) }
    }

    public let code: Code
    public let userInfo: [String: Any]
    private let reason: String?

    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.userInfo = userInfo
        reason = userInfo[NSLocalizedDescriptionKey] as? String
    }
    init(_ code: Code, reason: String) {
        self.code = code
        self.userInfo = [NSLocalizedDescriptionKey: reason]
        self.reason = reason
    }

    public var errorCode: Int { code.rawValue }
    public var failingURL: URL? { userInfo["NSErrorFailingURLKey"] as? URL }
    /// The address that failed, as text.
    public var failureURLString: String? { userInfo["NSErrorFailingURLStringKey"] as? String ?? failingURL?.absoluteString }
    public var localizedDescription: String { reason ?? description }
    public var errorDescription: String? { localizedDescription }
    public var description: String {
        switch code {
        case .cancelled: "cancelled"
        case .timedOut: "The request timed out."
        case .badURL: "bad URL"
        case .notConnectedToInternet: "The Internet connection appears to be offline."
        case .cannotConnectToHost: "Could not connect to the server."
        default: "URLError \(code.rawValue)"
        }
    }
    public static func == (lhs: URLError, rhs: URLError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }

    /// Why a request the system kept off the network failed: the browser's fetch never says, so
    /// this is nil unless the error was made with Foundation's key.
    public var networkUnavailableReason: NetworkUnavailableReason? {
        (userInfo["NSURLErrorNetworkUnavailableReasonKey"] as? Int).flatMap(NetworkUnavailableReason.init(rawValue:))
    }
    /// Why the system cancelled a background task: never, in a page.
    public var backgroundTaskCancelledReason: BackgroundTaskCancelledReason? {
        (userInfo["NSURLErrorBackgroundTaskCancelledReasonKey"] as? Int).flatMap(BackgroundTaskCancelledReason.init(rawValue:))
    }
    /// The data a cancelled download resumes from, when the error carries it.
    public var downloadTaskResumeData: Data? { userInfo["NSURLSessionDownloadTaskResumeData"] as? Data }

    /// The network a request was kept off, with Apple's raw values.
    public enum NetworkUnavailableReason: Int, Sendable {
        case cellular = 0
        case expensive = 1
        case constrained = 2
    }

    /// Why a background task was cancelled, with Apple's raw values.
    public enum BackgroundTaskCancelledReason: Int, Sendable {
        case userForceQuitApplication = 0
        case backgroundUpdatesDisabled = 1
        case insufficientSystemResources = 2
    }
}

/// Foundation names every code on `URLError` itself too (`URLError.cancelled`); computed, so an
/// app ships only the ones it names.
extension URLError {
    public static var unknown: Code { .unknown }
    public static var cancelled: Code { .cancelled }
    public static var badURL: Code { .badURL }
    public static var timedOut: Code { .timedOut }
    public static var unsupportedURL: Code { .unsupportedURL }
    public static var cannotFindHost: Code { .cannotFindHost }
    public static var cannotConnectToHost: Code { .cannotConnectToHost }
    public static var networkConnectionLost: Code { .networkConnectionLost }
    public static var resourceUnavailable: Code { .resourceUnavailable }
    public static var notConnectedToInternet: Code { .notConnectedToInternet }
    public static var badServerResponse: Code { .badServerResponse }
    public static var userCancelledAuthentication: Code { .userCancelledAuthentication }
    public static var cannotDecodeRawData: Code { .cannotDecodeRawData }
    public static var cannotParseResponse: Code { .cannotParseResponse }
    public static var secureConnectionFailed: Code { .secureConnectionFailed }
    public static var backgroundSessionRequiresSharedContainer: Code { .backgroundSessionRequiresSharedContainer }
    public static var backgroundSessionInUseByAnotherProcess: Code { .backgroundSessionInUseByAnotherProcess }
    public static var backgroundSessionWasDisconnected: Code { .backgroundSessionWasDisconnected }
    public static var dnsLookupFailed: Code { .dnsLookupFailed }
    public static var httpTooManyRedirects: Code { .httpTooManyRedirects }
    public static var redirectToNonExistentLocation: Code { .redirectToNonExistentLocation }
    public static var userAuthenticationRequired: Code { .userAuthenticationRequired }
    public static var zeroByteResource: Code { .zeroByteResource }
    public static var cannotDecodeContentData: Code { .cannotDecodeContentData }
    public static var internationalRoamingOff: Code { .internationalRoamingOff }
    public static var callIsActive: Code { .callIsActive }
    public static var dataNotAllowed: Code { .dataNotAllowed }
    public static var requestBodyStreamExhausted: Code { .requestBodyStreamExhausted }
    public static var appTransportSecurityRequiresSecureConnection: Code { .appTransportSecurityRequiresSecureConnection }
    public static var fileDoesNotExist: Code { .fileDoesNotExist }
    public static var fileIsDirectory: Code { .fileIsDirectory }
    public static var noPermissionsToReadFile: Code { .noPermissionsToReadFile }
    public static var dataLengthExceedsMaximum: Code { .dataLengthExceedsMaximum }
    public static var fileOutsideSafeArea: Code { .fileOutsideSafeArea }
    public static var serverCertificateHasBadDate: Code { .serverCertificateHasBadDate }
    public static var serverCertificateUntrusted: Code { .serverCertificateUntrusted }
    public static var serverCertificateHasUnknownRoot: Code { .serverCertificateHasUnknownRoot }
    public static var serverCertificateNotYetValid: Code { .serverCertificateNotYetValid }
    public static var clientCertificateRejected: Code { .clientCertificateRejected }
    public static var clientCertificateRequired: Code { .clientCertificateRequired }
    public static var cannotLoadFromNetwork: Code { .cannotLoadFromNetwork }
    public static var cannotCreateFile: Code { .cannotCreateFile }
    public static var cannotOpenFile: Code { .cannotOpenFile }
    public static var cannotCloseFile: Code { .cannotCloseFile }
    public static var cannotWriteToFile: Code { .cannotWriteToFile }
    public static var cannotRemoveFile: Code { .cannotRemoveFile }
    public static var cannotMoveFile: Code { .cannotMoveFile }
    public static var downloadDecodingFailedMidStream: Code { .downloadDecodingFailedMidStream }
    public static var downloadDecodingFailedToComplete: Code { .downloadDecodingFailedToComplete }
}

/// A configuration object that defines behavior and policies for a URL session.
public final class URLSessionConfiguration: @unchecked Sendable {
    public static var `default`: URLSessionConfiguration { URLSessionConfiguration() }
    public static var ephemeral: URLSessionConfiguration { URLSessionConfiguration() }
    public static func background(withIdentifier identifier: String) -> URLSessionConfiguration { URLSessionConfiguration() }

    public var timeoutIntervalForRequest: TimeInterval = 60
    public var timeoutIntervalForResource: TimeInterval = 7 * 24 * 3600
    public var httpAdditionalHeaders: [AnyHashable: Any]?
    public var requestCachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    public var urlCache: URLCache? = .shared
    public var allowsCellularAccess = true
    public var waitsForConnectivity = false
    public var httpMaximumConnectionsPerHost = 6
    public var httpShouldSetCookies = true
    /// Recorded: the browser's jar is what `fetch` sends (HTTPCookie.swift).
    public var httpCookieStorage: HTTPCookieStorage? = .shared
    public var httpCookieAcceptPolicy: HTTPCookieStorage.AcceptPolicy = .onlyFromMainDocumentDomain
    public var httpShouldUsePipelining = false
    public var isDiscretionary = false
    public var sessionSendsLaunchEvents = false
    public var networkServiceType: URLRequest.NetworkServiceType = .default
    /// Recorded: the browser answers HTTP authentication itself, so nothing reads it. Held
    /// untyped, and the shared storage named only when read, so a page that never asks links no
    /// credential storage (Counter's size budget).
    public var urlCredentialStorage: URLCredentialStorage? {
        get { _credentialStorageIsShared ? .shared : _credentialStorage.map { unsafeDowncast($0, to: URLCredentialStorage.self) } }
        set { _credentialStorageIsShared = false; _credentialStorage = newValue }
    }
    private var _credentialStorage: AnyObject?
    private var _credentialStorageIsShared = true
    public var identifier: String? { nil }
    public init() {}

    var core: _WebURLSession.Configuration {
        var configuration = _WebURLSession.Configuration()
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = timeoutIntervalForResource
        for (key, value) in httpAdditionalHeaders ?? [:] {
            if let key = key as? String, let value = value as? String { configuration.httpAdditionalHeaders[key] = value }
        }
        configuration.allowsCellularAccess = allowsCellularAccess
        configuration.waitsForConnectivity = waitsForConnectivity
        configuration.httpMaximumConnectionsPerHost = httpMaximumConnectionsPerHost
        configuration.httpShouldSetCookies = httpShouldSetCookies
        return configuration
    }
}

/// The browser's cache is the cache (`fetch` consults it); the object records the sizes asked for.
public final class URLCache: @unchecked Sendable {
    nonisolated(unsafe) public static var shared = URLCache(memoryCapacity: 512_000, diskCapacity: 10_000_000)
    public var memoryCapacity: Int
    public var diskCapacity: Int
    public var currentMemoryUsage: Int { 0 }
    public var currentDiskUsage: Int { 0 }
    public init(memoryCapacity: Int, diskCapacity: Int, diskPath: String? = nil) {
        self.memoryCapacity = memoryCapacity
        self.diskCapacity = diskCapacity
    }
    public func removeAllCachedResponses() {}
}

/// The size of a body that is not known (Foundation's `NSURLSessionTransferSizeUnknown`).
public let NSURLSessionTransferSizeUnknown: Int64 = -1
/// The user-info key of a failed download's resume data (never set: see
/// `URLSessionDownloadTask.cancel(byProducingResumeData:)`).
public let NSURLSessionDownloadTaskResumeData = "NSURLSessionDownloadTaskResumeData"

/// A task that retrieves the contents of a URL (cancellable; `resume` sends it). An `NSObject`,
/// so tasks key dictionaries by identity, as Alamofire's request map does.
open class URLSessionTask: NSObject, @unchecked Sendable {
    public enum State: Int, Sendable { case running = 0, suspended = 1, canceling = 2, completed = 3 }
    public let taskIdentifier: Int
    public let originalRequest: URLRequest?
    public internal(set) var currentRequest: URLRequest?
    public internal(set) var response: URLResponse?
    public internal(set) var error: Error?
    public private(set) var state: State = .suspended
    public var priority: Float = URLSessionTask.defaultPriority
    public var taskDescription: String?
    /// Whether the delegate hears the body as it arrives. A page's fetch delivers it whole, so
    /// the flag is stored only.
    public var prefersIncrementalDelivery = true
    public static let defaultPriority: Float = 0.5
    public static let lowPriority: Float = 0.25
    public static let highPriority: Float = 0.75
    private let start: @Sendable () -> _WebURLSession.Task
    var core: _WebURLSession.Task?

    init(identifier: Int, request: URLRequest, start: @escaping @Sendable () -> _WebURLSession.Task) {
        taskIdentifier = identifier
        originalRequest = request
        currentRequest = request
        self.start = start
        super.init()
    }

    /// Sends the request (a new task waits for this, as Foundation's does), or marks a
    /// suspended one running again.
    public func resume() {
        guard state == .suspended else { return }
        state = .running
        if core == nil { core = start() }
    }

    /// Marks the task suspended. A fetch the browser has started can't be paused, so its
    /// outcome still arrives; one not yet resumed waits, as it would anyway.
    public func suspend() {
        guard state == .running else { return }
        state = .suspended
    }

    public func cancel() {
        guard state == .running || state == .suspended else { return }
        state = .canceling
        if let core { core.cancel() } else { state = .completed; error = URLError(.cancelled) }
    }

    func finished(response: URLResponse?, error: Error?) {
        self.response = response
        self.error = error
        state = .completed
    }
}

open class URLSessionDataTask: URLSessionTask, @unchecked Sendable {}
open class URLSessionUploadTask: URLSessionDataTask, @unchecked Sendable {}

open class URLSessionDownloadTask: URLSessionTask, @unchecked Sendable {
    /// Cancels the download. The browser keeps no partial body to resume from, so the resume
    /// data is always nil and a download starts again from the beginning.
    public func cancel(byProducingResumeData completionHandler: @escaping @Sendable (Data?) -> Void) {
        cancel()
        completionHandler(nil)
    }
}

/// An object that coordinates a group of related, network data transfer tasks.
public final class URLSession: _WebObjectBase, @unchecked Sendable {
    public static let shared = URLSession(configuration: .default)
    public let configuration: URLSessionConfiguration
    public var sessionDescription: String?
    /// The delegate (URLSessionDelegate.swift), held until the session is invalidated, as
    /// Foundation holds it.
    public private(set) var delegate: (any URLSessionDelegate)?
    /// The queue given, or one made when first read, as a session makes its own. Held untyped,
    /// so a page that never names it links no OperationQueue (Counter's size budget).
    public var delegateQueue: OperationQueue {
        if let queue = _delegateQueue { return unsafeDowncast(queue, to: OperationQueue.self) }
        let queue = OperationQueue()
        _delegateQueue = queue
        return queue
    }
    private var _delegateQueue: AnyObject?
    let core: _WebURLSession
    private var nextTaskIdentifier = 1

    public init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
        core = _WebURLSession(configuration: configuration.core)
    }
    public init(configuration: URLSessionConfiguration, delegate: (any URLSessionDelegate)?, delegateQueue queue: OperationQueue?) {
        self.configuration = configuration
        core = _WebURLSession(configuration: configuration.core)
        self.delegate = delegate
        _delegateQueue = queue
    }

    /// Maps the host's answer: a response of any status is `(data, HTTPURLResponse)`; a
    /// failure is a `URLError`.
    static func outcome(_ outcome: _WebURLSession.Outcome, for url: URL) -> Result<(Data, URLResponse), URLError> {
        switch outcome {
        case .response(let response):
            let final = URL(string: response.url) ?? url
            let http = HTTPURLResponse(url: final, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
            return .success((Data(response.body), http))
        case .failure(let failure):
            switch failure {
            case .cancelled: return .failure(URLError(.cancelled))
            case .timedOut: return .failure(URLError(.timedOut))
            case .badURL: return .failure(URLError(.badURL))
            case .notConnected: return .failure(URLError(.notConnectedToInternet))
            case .unreachable(let reason): return .failure(URLError(.cannotConnectToHost, reason: reason))
            }
        }
    }

    /// A task of the kind `make` builds (a data, upload or download task), which sends
    /// `request` when resumed and hands its outcome to `completionHandler`. `body`, when given,
    /// supplies the body at that moment (a streamed upload's, from the delegate).
    func makeTask<Kind: URLSessionTask>(_ request: URLRequest,
                                        as make: (Int, URLRequest, @escaping @Sendable () -> _WebURLSession.Task) -> Kind,
                                        failure: URLError? = nil,
                                        body: (@Sendable (Kind) -> Data?)? = nil,
                                        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> Kind {
        let identifier = nextTaskIdentifier
        nextTaskIdentifier += 1
        guard let url = request.url, url.scheme != nil, failure == nil else {
            let error = failure ?? URLError(.badURL)
            let task = make(identifier, request) { _WebURLSession.Task(identifier: 0) { _ in } }
            task.finished(response: nil, error: error)
            completionHandler(nil, nil, error)
            return task
        }
        nonisolated(unsafe) var task: Kind!
        let core = self.core
        let timeout = request.timeoutInterval == 60 ? nil : request.timeoutInterval
        task = make(identifier, request) {
            let sent = body.map { $0(task) } ?? request.httpBody
            return core.send(url: url.absoluteString, method: request.httpMethod, headers: request.allHTTPHeaderFields,
                             body: sent.map { Array($0) }, timeout: timeout) { outcome in
                switch Self.outcome(outcome, for: url) {
                case .success(let (data, response)):
                    task.finished(response: response, error: nil)
                    completionHandler(data, response, nil)
                case .failure(let error):
                    task.finished(response: nil, error: error)
                    completionHandler(nil, nil, error)
                }
            }
        }
        return task
    }

    public func dataTask(with request: URLRequest, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        makeTask(request, as: URLSessionDataTask.init(identifier:request:start:), completionHandler: completionHandler)
    }
    public func dataTask(with url: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        makeTask(URLRequest(url: url), as: URLSessionDataTask.init(identifier:request:start:), completionHandler: completionHandler)
    }
    /// A task that reports to the delegate (URLSessionDelegate.swift).
    public func dataTask(with request: URLRequest) -> URLSessionDataTask { delegatedTask(request) }
    public func dataTask(with url: URL) -> URLSessionDataTask { delegatedTask(URLRequest(url: url)) }

    // MARK: Download and upload tasks

    /// Downloads to a file under the temporary directory and hands its URL to the handler; the
    /// file is removed once the handler returns, as Foundation removes it, so a handler that
    /// keeps it moves it first.
    public func downloadTask(with request: URLRequest, completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        makeTask(request, as: URLSessionDownloadTask.init(identifier:request:start:)) { data, response, error in
            guard let data, let response else { completionHandler(nil, response, error); return }
            do {
                let file = try Self.temporaryDownload(data)
                completionHandler(file, response, nil)
                try? FileManager.default.removeItem(at: file)
            } catch {
                completionHandler(nil, response, error)
            }
        }
    }
    public func downloadTask(with url: URL, completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        downloadTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }
    /// A download that reports to the delegate (`URLSessionDownloadDelegate`).
    public func downloadTask(with request: URLRequest) -> URLSessionDownloadTask { delegatedDownload(request) }
    public func downloadTask(with url: URL) -> URLSessionDownloadTask { delegatedDownload(URLRequest(url: url)) }
    /// No resume data is ever produced here, so a task made from some fails with
    /// `URLError.cannotDecodeContentData` once resumed.
    public func downloadTask(withResumeData resumeData: Data) -> URLSessionDownloadTask {
        delegatedDownload(Self.resumeRequest, failure: URLError(.cannotDecodeContentData))
    }
    public func downloadTask(withResumeData resumeData: Data, completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        makeTask(Self.resumeRequest, as: URLSessionDownloadTask.init(identifier:request:start:), failure: URLError(.cannotDecodeContentData)) { _, response, error in
            completionHandler(nil, response, error)
        }
    }
    static var resumeRequest: URLRequest { URLRequest(url: URL(fileURLWithPath: "/")) }

    /// Sends `bodyData` as the request's body (POST unless the request names another method).
    public func uploadTask(with request: URLRequest, from bodyData: Data?, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        makeTask(Self.uploading(request, bodyData), as: URLSessionUploadTask.init(identifier:request:start:), completionHandler: completionHandler)
    }
    /// Sends the file's contents; a file missing from the store fails with
    /// `URLError.fileDoesNotExist`.
    public func uploadTask(with request: URLRequest, fromFile fileURL: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let body = try? Data(contentsOf: fileURL)
        return makeTask(Self.uploading(request, body), as: URLSessionUploadTask.init(identifier:request:start:),
                        failure: body == nil ? URLError(.fileDoesNotExist) : nil, completionHandler: completionHandler)
    }
    /// An upload that reports to the delegate.
    public func uploadTask(with request: URLRequest, from bodyData: Data) -> URLSessionUploadTask {
        delegatedUpload(Self.uploading(request, bodyData), bodyCount: bodyData.count)
    }
    public func uploadTask(with request: URLRequest, fromFile fileURL: URL) -> URLSessionUploadTask {
        let body = try? Data(contentsOf: fileURL)
        return delegatedUpload(Self.uploading(request, body), bodyCount: body?.count ?? 0, failure: body == nil ? URLError(.fileDoesNotExist) : nil)
    }
    /// Asks the delegate for the body (`urlSession(_:task:needNewBodyStream:)`) when resumed,
    /// reads the whole stream, then sends it.
    public func uploadTask(withStreamedRequest request: URLRequest) -> URLSessionUploadTask { streamedUpload(request) }

    static func uploading(_ request: URLRequest, _ body: Data?) -> URLRequest {
        var uploading = request
        uploading.httpBody = body
        if uploading.httpMethod == nil || uploading.httpMethod == "GET" { uploading.httpMethod = "POST" }
        return uploading
    }

    /// Writes a download's body to a new file under the temporary directory (the in-memory file
    /// system on wasm).
    static func temporaryDownload(_ data: Data) throws -> URL {
        let name = "CFNetworkDownload_" + String(UInt64(Date().timeIntervalSince1970 * 1000), radix: 36) + "_" + String(data.count) + ".tmp"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    /// Retrieves the contents of a URL request and delivers the data asynchronously; a
    /// cancelled Swift task cancels the request (`URLError.cancelled`).
    /// A `delegate` is accepted for the forms that take one; the browser reports no progress
    /// while a body goes out, so an upload tells it once, when the body is sent.
    public func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        guard let url = request.url, url.scheme != nil else { throw URLError(.badURL) }
        // A task cancelled before the request goes out never sends it (Foundation's behaviour).
        if Task.isCancelled { throw URLError(.cancelled) }
        let inFlight = _Box<(task: _WebURLSession.Task?, cancelled: Bool)>((nil, false))
        let core = self.core
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                if inFlight.value.cancelled { continuation.resume(throwing: URLError(.cancelled)); return }
                inFlight.value.task = core.send(url: url.absoluteString, method: request.httpMethod, headers: request.allHTTPHeaderFields,
                                                body: request.httpBody.map { Array($0) }, timeout: request.timeoutInterval == 60 ? nil : request.timeoutInterval) { outcome in
                    switch Self.outcome(outcome, for: url) {
                    case .success(let pair): continuation.resume(returning: pair)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            inFlight.value.cancelled = true
            inFlight.value.task?.cancel()
        }
    }

    public func data(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) { try await data(for: URLRequest(url: url)) }

    /// Downloads to a file under the temporary directory (the in-memory file system on wasm,
    /// `Data(contentsOf:)` reads it back, as the Countries image repository does) and answers
    /// its URL with the response; an HTTP error status is still a response.
    public func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
        let (data, response) = try await data(for: request)
        return (try Self.temporaryDownload(data), response)
    }
    public func download(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) { try await download(for: URLRequest(url: url)) }

    /// Uploads `bodyData` with the request's method (POST unless the request says otherwise).
    public func upload(for request: URLRequest, from bodyData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        let uploading = Self.uploading(request, bodyData)
        let result = try await data(for: uploading)
        if let delegate {
            let task = URLSessionUploadTask(identifier: nextTaskIdentifier, request: uploading) { _WebURLSession.Task(identifier: 0) { _ in } }
            nextTaskIdentifier += 1
            task.finished(response: result.1, error: nil)
            let sent = Int64(bodyData.count)
            delegate.urlSession(self, task: task, didSendBodyData: sent, totalBytesSent: sent, totalBytesExpectedToSend: sent)
            delegate.urlSession(self, task: task, didCompleteWithError: nil)
        }
        return result
    }

    /// Cancels the session's tasks, tells the delegate the session is invalid and lets it go.
    public func invalidateAndCancel() {
        core.cancelAll()
        invalidate()
    }
    /// Lets running tasks finish; tells the delegate the session is invalid and lets it go.
    public func finishTasksAndInvalidate() { invalidate() }

    private func invalidate() {
        guard let delegate else { return }
        self.delegate = nil
        delegate.urlSession(self, didBecomeInvalidWithError: nil)
    }
    public func getAllTasks(completionHandler: @escaping ([URLSessionTask]) -> Void) { completionHandler([]) }
}

final class _Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}


#endif
