// Foundation's `URLProtocol` on wasm: the class an app subclasses to answer requests itself
// (OscarWeather's screenshot mode serves fixtures from one), its client protocol, the class
// registry and the per-request properties. The browser's `fetch` loads every request a page's
// sessions send, so a registered class is kept and answered from `registerClass(_:)`, but no
// session asks it to load (Foundation builds each loader from its class through the Objective-C
// runtime, which a required initializer would stand in for, at the cost of subclasses that
// override `init(request:cachedResponse:client:)` as Apple's SDK lets them).
#if os(WASI)

/// What a protocol tells the loading system as it loads.
public protocol URLProtocolClient: NSObjectProtocol {
    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse)
    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse)
    func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy)
    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data)
    func urlProtocolDidFinishLoading(_ protocol: URLProtocol)
    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: any Error)
    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge)
    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge)
}

/// A loader for the requests it says it can answer.
open class URLProtocol: NSObject, @unchecked Sendable {
    nonisolated(unsafe) private static var registered: [ObjectIdentifier] = []

    private let _request: URLRequest
    private let _cachedResponse: CachedURLResponse?
    private let _client: (any URLProtocolClient)?
    private weak var _task: URLSessionTask?

    public init(request: URLRequest, cachedResponse: CachedURLResponse?, client: (any URLProtocolClient)?) {
        _request = request
        _cachedResponse = cachedResponse
        _client = client
        super.init()
    }

    public convenience init(task: URLSessionTask, cachedResponse: CachedURLResponse?, client: (any URLProtocolClient)?) {
        self.init(request: task.currentRequest ?? task.originalRequest ?? URLRequest(url: URL(fileURLWithPath: "/")),
                  cachedResponse: cachedResponse, client: client)
        _task = task
    }

    open var client: (any URLProtocolClient)? { _client }
    open var request: URLRequest { _request }
    open var cachedResponse: CachedURLResponse? { _cachedResponse }
    open var task: URLSessionTask? { _task }

    /// Whether this class can load the request; the base class answers no.
    open class func canInit(with request: URLRequest) -> Bool { false }
    open class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest ?? task.originalRequest else { return false }
        return canInit(with: request)
    }
    open class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    open class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        canonicalRequest(for: a) == canonicalRequest(for: b)
    }

    open func startLoading() {}
    open func stopLoading() {}

    /// Adds a class to the ones consulted first; true for a `URLProtocol` subclass.
    @discardableResult
    open class func registerClass(_ protocolClass: AnyClass) -> Bool {
        guard protocolClass is URLProtocol.Type else { return false }
        let id = ObjectIdentifier(protocolClass)
        registered.removeAll { $0 == id }
        registered.insert(id, at: 0)
        return true
    }

    open class func unregisterClass(_ protocolClass: AnyClass) {
        let id = ObjectIdentifier(protocolClass)
        registered.removeAll { $0 == id }
    }

    /// A property a protocol set on the request. Foundation keeps them inside its request
    /// object; a `URLRequest` here is a plain value with none.
    open class func property(forKey key: String, in request: URLRequest) -> Any? { nil }
}
#endif
