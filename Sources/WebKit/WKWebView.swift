// WebKit's UIKit face (decision 0021, the Ember app's account sheets and in-app reader):
// `WKWebView` and the objects around it — its configuration, the website data store and its
// cookie store, user scripts and content controllers, the navigation delegate. The view is a
// UIKit view; where the hosted tree is painted into a browser canvas, the host's `<iframe>`
// takes the view's frame (`_UIHostElementProviding`) and shows the page the view loaded.
//
// What a frame of another origin cannot do, this view cannot: `evaluateJavaScript` on a
// cross-origin page answers with an error (the browser's same-origin rule), user scripts are
// kept and not injected, the cookie store holds the app's own cookies and never the page's
// (the browser hides them from a page), and navigation inside the frame is not observed —
// `didFinish` is reported for the load the view started, with the URL it was given.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftUI

// MARK: - Navigation

/// An object that tracks the loading progress of a webpage.
public final class WKNavigation: NSObject {
    public let effectiveContentMode: WKWebpagePreferences.ContentMode = .recommended
    override init() { super.init() }
}

public enum WKNavigationType: Int, Sendable {
    case linkActivated = 0, formSubmitted, backForward, reload, formResubmitted
    case other = -1
}

public enum WKNavigationActionPolicy: Int, Sendable {
    case cancel = 0, allow, download
}

public enum WKNavigationResponsePolicy: Int, Sendable {
    case cancel = 0, allow, download
}

/// An object that contains information about an action that causes navigation to occur.
public final class WKNavigationAction: NSObject {
    public let request: URLRequest
    public let navigationType: WKNavigationType
    public let targetFrame: WKFrameInfo?
    public let sourceFrame: WKFrameInfo
    public let shouldPerformDownload = false
    init(request: URLRequest, navigationType: WKNavigationType) {
        self.request = request
        self.navigationType = navigationType
        sourceFrame = WKFrameInfo(isMainFrame: true, request: request)
        targetFrame = sourceFrame
    }
}

public final class WKNavigationResponse: NSObject {
    public let isForMainFrame = true
    public let response: URLResponse
    public let canShowMIMEType = true
    init(response: URLResponse) { self.response = response }
}

public final class WKFrameInfo: NSObject {
    public let isMainFrame: Bool
    public let request: URLRequest
    public var securityOrigin: WKSecurityOrigin { WKSecurityOrigin(url: request.url) }
    init(isMainFrame: Bool, request: URLRequest) {
        self.isMainFrame = isMainFrame
        self.request = request
    }
}

public final class WKSecurityOrigin: NSObject {
    public let `protocol`: String
    public let host: String
    public let port: Int
    init(url: URL?) {
        `protocol` = url?.scheme ?? ""
        host = url?.host ?? ""
        port = url?.port ?? 0
    }
}

/// Methods for accepting or rejecting navigation changes, and for tracking the progress of
/// navigation requests. Every method has a default that does nothing (allows).
@MainActor
public protocol WKNavigationDelegate: AnyObject {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!)
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!)
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error)
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView)
}

extension WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) { decisionHandler(.allow) }
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) { decisionHandler(.allow, preferences) }
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) { decisionHandler(.allow) }
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {}
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {}
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {}
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {}
}

/// Methods for presenting native user interface elements on behalf of a webpage.
@MainActor
public protocol WKUIDelegate: AnyObject {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView?
    func webViewDidClose(_ webView: WKWebView)
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void)
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void)
}

extension WKUIDelegate {
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    public func webViewDidClose(_ webView: WKWebView) {}
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) { completionHandler() }
    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) { completionHandler(false) }
}

public final class WKWindowFeatures: NSObject {
    public let menuBarVisibility: NSNumber? = nil
    public let statusBarVisibility: NSNumber? = nil
    public let toolbarsVisibility: NSNumber? = nil
    public let allowsResizing: NSNumber? = nil
    public let x: NSNumber? = nil
    public let y: NSNumber? = nil
    public let width: NSNumber? = nil
    public let height: NSNumber? = nil
}

// MARK: - Configuration

/// A collection of properties that you use to initialize a web view.
public final class WKWebViewConfiguration: NSObject {
    public var websiteDataStore: WKWebsiteDataStore = .default()
    public var userContentController = WKUserContentController()
    public var preferences = WKPreferences()
    public var defaultWebpagePreferences = WKWebpagePreferences()
    public var applicationNameForUserAgent: String?
    public var allowsInlineMediaPlayback = false
    public var allowsAirPlayForMediaPlayback = true
    public var allowsPictureInPictureMediaPlayback = true
    public var suppressesIncrementalRendering = false
    public var ignoresViewportScaleLimits = false
    public var limitsNavigationsToAppBoundDomains = false
    public var upgradeKnownHostsToHTTPS = false
    public var mediaTypesRequiringUserActionForPlayback: WKAudiovisualMediaTypes = .all
    public var dataDetectorTypes: WKDataDetectorTypes = []
    public var processPool = WKProcessPool()
    public override init() { super.init() }

    public func setURLSchemeHandler(_ urlSchemeHandler: (any WKURLSchemeHandler)?, forURLScheme urlScheme: String) {
        schemeHandlers[urlScheme] = urlSchemeHandler
    }
    public func urlSchemeHandler(forURLScheme urlScheme: String) -> (any WKURLSchemeHandler)? { schemeHandlers[urlScheme] }
    private var schemeHandlers: [String: any WKURLSchemeHandler] = [:]
}

public protocol WKURLSchemeHandler: AnyObject {}

public final class WKProcessPool: NSObject {
    public override init() { super.init() }
}

public final class WKPreferences: NSObject {
    public var minimumFontSize: CGFloat = 0
    public var javaScriptCanOpenWindowsAutomatically = false
    public var isFraudulentWebsiteWarningEnabled = true
    public var isTextInteractionEnabled = true
    public var isElementFullscreenEnabled = false
    public var isSiteSpecificQuirksModeEnabled = true
    public var inactiveSchedulingPolicy: WKInactiveSchedulingPolicy = .suspend
    public override init() { super.init() }
}

public enum WKInactiveSchedulingPolicy: Int, Sendable {
    case suspend = 0, throttle, none
}

public final class WKWebpagePreferences: NSObject {
    public enum ContentMode: Int, Sendable {
        case recommended = 0, mobile, desktop
    }
    public enum UpgradeToHTTPSPolicy: Int, Sendable {
        case keepAsRequested = 0, automaticFallbackToHTTP, userMediatedFallbackToHTTP, errorOnFailure
    }
    public var preferredContentMode: ContentMode = .recommended
    public var allowsContentJavaScript = true
    public var preferredHTTPSNavigationPolicy: UpgradeToHTTPSPolicy = .keepAsRequested
    public var isLockdownModeEnabled = false
    public override init() { super.init() }
}

public struct WKAudiovisualMediaTypes: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let audio = WKAudiovisualMediaTypes(rawValue: 1)
    public static let video = WKAudiovisualMediaTypes(rawValue: 2)
    public static let all: WKAudiovisualMediaTypes = [.audio, .video]
}

public struct WKDataDetectorTypes: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let phoneNumber = WKDataDetectorTypes(rawValue: 1)
    public static let link = WKDataDetectorTypes(rawValue: 2)
    public static let address = WKDataDetectorTypes(rawValue: 4)
    public static let calendarEvent = WKDataDetectorTypes(rawValue: 8)
    public static let all = WKDataDetectorTypes(rawValue: 0xFFFF)
}

// MARK: - User scripts and messages

public enum WKUserScriptInjectionTime: Int, Sendable {
    case atDocumentStart = 0, atDocumentEnd
}

/// A script that the web view injects into a webpage. Kept, not injected: a frame of another
/// origin takes no script from the page around it.
public final class WKUserScript: NSObject {
    public let source: String
    public let injectionTime: WKUserScriptInjectionTime
    public let isForMainFrameOnly: Bool
    public let contentWorld: WKContentWorld
    public init(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool) {
        self.source = source
        self.injectionTime = injectionTime
        isForMainFrameOnly = forMainFrameOnly
        contentWorld = .page
        super.init()
    }
    public init(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool, in contentWorld: WKContentWorld) {
        self.source = source
        self.injectionTime = injectionTime
        isForMainFrameOnly = forMainFrameOnly
        self.contentWorld = contentWorld
        super.init()
    }
}

public final class WKContentWorld: NSObject {
    public let name: String?
    nonisolated(unsafe) public static let page = WKContentWorld(name: nil)
    nonisolated(unsafe) public static let defaultClient = WKContentWorld(name: "defaultClient")
    public static func world(name: String) -> WKContentWorld { WKContentWorld(name: name) }
    private init(name: String?) { self.name = name }
}

public protocol WKScriptMessageHandler: AnyObject {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
}

public final class WKScriptMessage: NSObject {
    public let body: Any
    public let name: String
    public let frameInfo: WKFrameInfo
    public weak var webView: WKWebView?
    init(body: Any, name: String, frameInfo: WKFrameInfo, webView: WKWebView?) {
        self.body = body
        self.name = name
        self.frameInfo = frameInfo
        self.webView = webView
    }
}

/// An object for managing interactions between JavaScript code and your web view.
public final class WKUserContentController: NSObject {
    public private(set) var userScripts: [WKUserScript] = []
    private var handlers: [String: any WKScriptMessageHandler] = [:]
    public override init() { super.init() }

    public func addUserScript(_ userScript: WKUserScript) { userScripts.append(userScript) }
    public func removeAllUserScripts() { userScripts.removeAll() }
    public func add(_ scriptMessageHandler: any WKScriptMessageHandler, name: String) { handlers[name] = scriptMessageHandler }
    public func add(_ scriptMessageHandler: any WKScriptMessageHandler, contentWorld: WKContentWorld, name: String) { handlers[name] = scriptMessageHandler }
    public func removeScriptMessageHandler(forName name: String) { handlers[name] = nil }
    public func removeAllScriptMessageHandlers() { handlers.removeAll() }
}

// MARK: - Website data

/// An object that manages cookies, disk and memory caches, and other types of data used by a
/// webpage. The browser's own stores are the frame's; this one keeps the app's cookies.
public final class WKWebsiteDataStore: NSObject {
    nonisolated(unsafe) private static let shared = WKWebsiteDataStore(persistent: true)
    public static func `default`() -> WKWebsiteDataStore { shared }
    public static func nonPersistent() -> WKWebsiteDataStore { WKWebsiteDataStore(persistent: false) }
    public static func allDataTypes() -> Set<String> { [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache] }

    public let isPersistent: Bool
    public let httpCookieStore: WKHTTPCookieStore
    public let identifier: UUID? = nil

    private init(persistent: Bool) {
        isPersistent = persistent
        #if os(WASI)
        httpCookieStore = WKHTTPCookieStore(storage: persistent ? .shared : HTTPCookieStorage())
        #else
        httpCookieStore = WKHTTPCookieStore(storage: .shared)   // corelibs Foundation keeps the initializer private
        #endif
        super.init()
    }

    public func fetchDataRecords(ofTypes dataTypes: Set<String>, completionHandler: @escaping ([WKWebsiteDataRecord]) -> Void) { completionHandler([]) }
    public func dataRecords(ofTypes dataTypes: Set<String>) async -> [WKWebsiteDataRecord] { [] }
    public func removeData(ofTypes dataTypes: Set<String>, for dataRecords: [WKWebsiteDataRecord], completionHandler: @escaping () -> Void) { completionHandler() }
    public func removeData(ofTypes dataTypes: Set<String>, modifiedSince date: Date, completionHandler: @escaping () -> Void) {
        if dataTypes.contains(WKWebsiteDataTypeCookies) { httpCookieStore.storage.removeCookies(since: date) }
        completionHandler()
    }
    public func removeData(ofTypes dataTypes: Set<String>, modifiedSince date: Date) async {
        if dataTypes.contains(WKWebsiteDataTypeCookies) { httpCookieStore.storage.removeCookies(since: date) }
    }
}

public let WKWebsiteDataTypeCookies = "WKWebsiteDataTypeCookies"
public let WKWebsiteDataTypeLocalStorage = "WKWebsiteDataTypeLocalStorage"
public let WKWebsiteDataTypeDiskCache = "WKWebsiteDataTypeDiskCache"
public let WKWebsiteDataTypeMemoryCache = "WKWebsiteDataTypeMemoryCache"
public let WKWebsiteDataTypeSessionStorage = "WKWebsiteDataTypeSessionStorage"

public final class WKWebsiteDataRecord: NSObject {
    public let displayName: String
    public let dataTypes: Set<String>
    init(displayName: String, dataTypes: Set<String>) {
        self.displayName = displayName
        self.dataTypes = dataTypes
    }
}

/// An object that manages the HTTP cookies associated with a particular web view data store.
public final class WKHTTPCookieStore: NSObject {
    let storage: HTTPCookieStorage
    private var observers: [ObjectIdentifier: any WKHTTPCookieStoreObserver] = [:]
    init(storage: HTTPCookieStorage) { self.storage = storage }

    public func getAllCookies(_ completionHandler: @escaping ([HTTPCookie]) -> Void) { completionHandler(storage.cookies ?? []) }
    public func allCookies() async -> [HTTPCookie] { storage.cookies ?? [] }
    public func setCookie(_ cookie: HTTPCookie, completionHandler: (() -> Void)? = nil) {
        storage.setCookie(cookie)
        changed()
        completionHandler?()
    }
    public func setCookie(_ cookie: HTTPCookie) async { storage.setCookie(cookie); changed() }
    public func delete(_ cookie: HTTPCookie, completionHandler: (() -> Void)? = nil) {
        storage.deleteCookie(cookie)
        changed()
        completionHandler?()
    }
    public func deleteCookie(_ cookie: HTTPCookie) async { storage.deleteCookie(cookie); changed() }
    public func add(_ observer: any WKHTTPCookieStoreObserver) { observers[ObjectIdentifier(observer)] = observer }
    public func remove(_ observer: any WKHTTPCookieStoreObserver) { observers[ObjectIdentifier(observer)] = nil }
    private func changed() { for observer in observers.values { observer.cookiesDidChange(in: self) } }
}

public protocol WKHTTPCookieStoreObserver: AnyObject {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore)
}

// MARK: - The view

/// An object that displays interactive web content, such as for an in-app browser.
@MainActor
open class WKWebView: UIView, _UIHostElementProviding {
    public let configuration: WKWebViewConfiguration
    open weak var navigationDelegate: (any WKNavigationDelegate)?
    open weak var uiDelegate: (any WKUIDelegate)?
    public private(set) var url: URL?
    public private(set) var title: String?
    public private(set) var isLoading = false
    public private(set) var estimatedProgress: Double = 0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    open var allowsBackForwardNavigationGestures = false
    open var allowsLinkPreview = true
    open var customUserAgent: String?
    open var isInspectable = false
    open var underPageBackgroundColor: UIColor? { didSet { backgroundColor = underPageBackgroundColor ?? .white } }
    public private(set) var hasOnlySecureContent = true
    public let scrollView = UIScrollView()
    public private(set) var backForwardList = WKBackForwardList()
    private var html: String?
    private var navigation: WKNavigation?
    private let placeholder = UILabel()

    public init(frame: CGRect, configuration: WKWebViewConfiguration) {
        self.configuration = configuration
        super.init(frame: frame)
        backgroundColor = .white
        placeholder.textAlignment = .center
        placeholder.textColor = .secondaryLabel
        placeholder.font = .systemFont(ofSize: 13)
        placeholder.numberOfLines = 0
        addSubview(placeholder)
    }

    public convenience override init(frame: CGRect) {
        self.init(frame: frame, configuration: WKWebViewConfiguration())
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        placeholder.frame = bounds.insetBy(dx: 16, dy: 16)
    }

    /// The host's element: the frame shows the loaded page where the view is.
    public var _hostElementKind: HostElement.Kind? {
        guard url != nil || html != nil else { return nil }
        return .web(url: url?.absoluteString, html: html)
    }

    // MARK: Loading

    /// Loads the web content that the specified URL request object references.
    @discardableResult
    open func load(_ request: URLRequest) -> WKNavigation? {
        guard let target = request.url else { return nil }
        return begin(url: target, html: nil)
    }

    @discardableResult
    open func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        begin(url: baseURL, html: string)
    }

    @discardableResult
    open func load(_ data: Data, mimeType MIMEType: String, characterEncodingName: String, baseURL: URL) -> WKNavigation? {
        begin(url: baseURL, html: String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    open func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        begin(url: URL, html: nil)
    }

    @discardableResult
    open func reload() -> WKNavigation? {
        guard url != nil || html != nil else { return nil }
        return begin(url: url, html: html)
    }

    @discardableResult
    open func reloadFromOrigin() -> WKNavigation? { reload() }

    open func stopLoading() {
        isLoading = false
    }

    @discardableResult
    open func goBack() -> WKNavigation? { nil }
    @discardableResult
    open func goForward() -> WKNavigation? { nil }
    @discardableResult
    open func go(to item: WKBackForwardListItem) -> WKNavigation? { nil }

    /// The load: the delegate's policy, then the frame takes the page and the finish is
    /// reported for it (a frame of another origin says nothing about what it shows).
    private func begin(url target: URL?, html: String?) -> WKNavigation {
        let navigation = WKNavigation()
        self.navigation = navigation
        let request = URLRequest(url: target ?? URL(string: "about:blank")!)
        let action = WKNavigationAction(request: request, navigationType: .other)
        let proceed = { [weak self] in
            guard let self else { return }
            self.url = target
            self.html = html
            self.title = target?.host
            self.isLoading = true
            self.estimatedProgress = 0.1
            // Under the frame: seen only where the page paints nothing, which is what a site
            // that refuses to be framed (Hacker News's login) leaves. The host's Open link over
            // the frame's corner takes it to a tab of its own.
            self.placeholder.text = target.map { "\($0.absoluteString)\n\nThis site does not show itself inside another site. Open \u{2197} shows it in a new tab." } ?? ""
            self.setNeedsLayout()
            self.hostElementDidChange()
            self.navigationDelegate?.webView(self, didStartProvisionalNavigation: navigation)
            self.navigationDelegate?.webView(self, didCommit: navigation)
            // The frame loads on its own; the finish follows on the next turn, as a load's would.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.navigation === navigation else { return }
                self.isLoading = false
                self.estimatedProgress = 1
                self.navigationDelegate?.webView(self, didFinish: navigation)
            }
        }
        if let delegate = navigationDelegate {
            delegate.webView(self, decidePolicyFor: action, preferences: configuration.defaultWebpagePreferences) { policy, _ in
                if policy == .allow { proceed() }
            }
        } else {
            proceed()
        }
        return navigation
    }

    /// The view's frame changed what the host should show.
    func hostElementDidChange() {
        setNeedsDisplay()
        _hostElementsDidChange?()
    }

    /// Set by the hosting tree so a change of page re-collects the elements.
    public var _hostElementsDidChange: (() -> Void)?

    // MARK: Scripts

    /// Evaluates JavaScript in the page. A page of another origin is closed to the page around
    /// it: the completion gets the browser's refusal as an error, as WebKit's does for a
    /// failed evaluation.
    open func evaluateJavaScript(_ javaScriptString: String, completionHandler: (@MainActor (Any?, (any Error)?) -> Void)? = nil) {
        let error = WKError(.javaScriptExceptionOccurred, message: "WKWebView: the page's origin is not the app's; a script cannot run in it")
        DispatchQueue.main.async { completionHandler?(nil, error) }
    }

    @discardableResult
    open func evaluateJavaScript(_ javaScript: String) async throws -> Any? {
        throw WKError(.javaScriptExceptionOccurred, message: "WKWebView: the page's origin is not the app's; a script cannot run in it")
    }

    open func callAsyncJavaScript(_ functionBody: String, arguments: [String: Any] = [:], in frame: WKFrameInfo? = nil, in contentWorld: WKContentWorld) async throws -> Any? {
        throw WKError(.javaScriptExceptionOccurred, message: "WKWebView: the page's origin is not the app's; a script cannot run in it")
    }

    // MARK: Snapshots

    open func takeSnapshot(with snapshotConfiguration: WKSnapshotConfiguration?, completionHandler: @escaping (UIImage?, (any Error)?) -> Void) {
        completionHandler(nil, WKError(.unknown, message: "WKWebView: a frame cannot be snapshotted"))
    }
}

public final class WKSnapshotConfiguration: NSObject {
    public var rect: CGRect = .null
    public var snapshotWidth: NSNumber?
    public var afterScreenUpdates = true
    public override init() { super.init() }
}

public final class WKBackForwardList: NSObject {
    public var currentItem: WKBackForwardListItem? { nil }
    public var backItem: WKBackForwardListItem? { nil }
    public var forwardItem: WKBackForwardListItem? { nil }
    public var backList: [WKBackForwardListItem] { [] }
    public var forwardList: [WKBackForwardListItem] { [] }
}

public final class WKBackForwardListItem: NSObject {
    public let url: URL
    public let title: String?
    public let initialURL: URL
    init(url: URL, title: String?) {
        self.url = url
        self.title = title
        initialURL = url
    }
}

/// WebKit's errors.
public struct WKError: Error, CustomStringConvertible, LocalizedError {
    public enum Code: Int, Sendable {
        case unknown = 1, webContentProcessTerminated, webViewInvalidated, javaScriptExceptionOccurred, javaScriptResultTypeIsUnsupported
        case contentRuleListStoreCompileFailed, contentRuleListStoreLookUpFailed, contentRuleListStoreRemoveFailed, contentRuleListStoreVersionMismatch
        case attributedStringContentFailedToLoad, attributedStringContentLoadTimedOut, javaScriptInvalidFrameTarget, navigationAppBoundDomain, javaScriptAppBoundDomain
    }
    public static let errorDomain = "WKErrorDomain"
    public let code: Code
    public let message: String
    public init(_ code: Code, message: String = "") {
        self.code = code
        self.message = message
    }
    public var errorCode: Int { code.rawValue }
    public var description: String { message.isEmpty ? "WKError \(code)" : message }
    public var errorDescription: String? { description }
}
