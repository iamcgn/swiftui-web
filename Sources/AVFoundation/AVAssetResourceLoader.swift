// An asset's resource loader: the delegate an app sets to hand AVFoundation a movie's bytes for a
// URL the player cannot fetch itself (Mlem's NukeVideo plays a downloaded clip from memory through
// an `in-memory-data://` URL). The browser's `<video>` element cannot ask an app for bytes, so
// when an asset's URL has a scheme the browser cannot load and the asset has a delegate, the
// asset asks the delegate once, for the whole resource from its start, and plays what the
// delegate answers with from a URL the browser can load: an object URL the host makes for the
// bytes (`_AVFrameHost.objectURL`, which SwiftUIWebCanvas installs), or a `data:` URL without a
// host. A delegate that answers later, from its queue, is not waited for: the asset then keeps its
// own URL, which the element cannot play.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import AVCaptureHost

/// What an asset's resource loader asks of the app: whether it will load a resource.
public protocol AVAssetResourceLoaderDelegate: AnyObject {
    /// Whether the delegate will load the requested resource (answering the request, now or later).
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool
    /// Whether the delegate will renew a resource it loaded before.
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool
    /// The loader no longer needs the resource.
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest)
}

extension AVAssetResourceLoaderDelegate {
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool { false }
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool { false }
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {}
}

/// The loader an `AVURLAsset` asks for resources its URL does not reach.
public final class AVAssetResourceLoader: NSObject, @unchecked Sendable {
    public private(set) weak var delegate: (any AVAssetResourceLoaderDelegate)?
    public private(set) var delegateQueue: DispatchQueue?
    /// Accepted for FairPlay keys, which a page has none of.
    public var preloadsEligibleContentKeys = false

    override init() { super.init() }

    /// Sets the delegate, and the queue Apple's loader calls it on (it is called at once here).
    public func setDelegate(_ delegate: (any AVAssetResourceLoaderDelegate)?, queue: DispatchQueue?) {
        self.delegate = delegate
        delegateQueue = queue
    }

    /// The bytes the delegate answers for `url` with and their type, if it answers at once.
    func load(_ url: URL) -> (data: Data, contentType: String?)? {
        guard let delegate else { return nil }
        let request = AVAssetResourceLoadingRequest(request: URLRequest(url: url))
        guard delegate.resourceLoader(self, shouldWaitForLoadingOfRequestedResource: request) else { return nil }
        guard let dataRequest = request.dataRequest, !dataRequest.received.isEmpty, !request.isCancelled else { return nil }
        return (dataRequest.received, request.contentInformationRequest?.contentType)
    }
}

/// One request for a resource: what is wanted, and how the delegate answers it.
public class AVAssetResourceLoadingRequest: NSObject, @unchecked Sendable {
    public let request: URLRequest
    /// Where the delegate says what the resource is (its type and length).
    public let contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?
    /// The bytes wanted, which the delegate answers with.
    public let dataRequest: AVAssetResourceLoadingDataRequest?
    public var response: URLResponse?
    public var redirect: URLRequest?
    public private(set) var isFinished = false
    public private(set) var isCancelled = false
    /// The error the delegate finished with, if any.
    public private(set) var error: (any Error)?

    init(request: URLRequest) {
        self.request = request
        contentInformationRequest = AVAssetResourceLoadingContentInformationRequest()
        dataRequest = AVAssetResourceLoadingDataRequest(requestedOffset: 0, requestedLength: Int.max, toEnd: true)
        super.init()
    }

    /// The delegate has answered the whole request.
    public func finishLoading() { isFinished = true }
    /// The delegate could not load the resource.
    public func finishLoading(with error: (any Error)?) {
        self.error = error
        isFinished = true
        isCancelled = error != nil
    }
}

/// A request to renew a resource (for keys, which a page does not use).
public final class AVAssetResourceRenewalRequest: AVAssetResourceLoadingRequest, @unchecked Sendable {}

/// What the delegate says about the resource.
public final class AVAssetResourceLoadingContentInformationRequest: NSObject, @unchecked Sendable {
    /// The resource's type, as a uniform type identifier (`AVFileType`'s raw value) or MIME type.
    public var contentType: String?
    /// The types the loader takes (any).
    public var allowedContentTypes: [String]? { nil }
    public var contentLength: Int64 = 0
    public var isByteRangeAccessSupported = false
    public var isEntireLengthAvailableOnDemand = false
    public var renewalDate: Date?
}

/// The bytes wanted from the resource: here always all of it, from its start.
public final class AVAssetResourceLoadingDataRequest: NSObject, @unchecked Sendable {
    public let requestedOffset: Int64
    public let requestedLength: Int
    public let requestsAllDataToEndOfResource: Bool
    /// Where the next bytes the delegate answers with go.
    public var currentOffset: Int64 { requestedOffset + Int64(received.count) }
    private(set) var received = Data()

    init(requestedOffset: Int64, requestedLength: Int, toEnd: Bool) {
        self.requestedOffset = requestedOffset
        self.requestedLength = requestedLength
        requestsAllDataToEndOfResource = toEnd
        super.init()
    }

    /// Answers with the next bytes of the resource.
    public func respond(with data: Data) { received.append(data) }
}

extension AVURLAsset {
    /// The schemes the browser's element loads itself.
    static let webSchemes: Set<String> = ["http", "https", "file", "blob", "data"]

    /// A URL for bytes the delegate answered with: the host's object URL, or a `data:` URL.
    static func playableURL(for data: Data, contentType: String?) -> URL? {
        let mime = mimeType(contentType)
        if let host = _AVFrameHost.objectURL, let made = host(Array(data), mime), let url = URL(string: made) { return url }
        return URL(string: "data:\(mime);base64,\(data.base64EncodedString())")
    }

    /// The MIME type for a type identifier (or the MIME type the delegate gave).
    static func mimeType(_ contentType: String?) -> String {
        switch contentType {
        case AVFileType.mov.rawValue: return "video/quicktime"
        case AVFileType.mp4.rawValue: return "video/mp4"
        case AVFileType.m4v.rawValue: return "video/x-m4v"
        case AVFileType.m4a.rawValue: return "audio/mp4"
        case let type? where type.contains("/"): return type
        default: return "application/octet-stream"
        }
    }
}
