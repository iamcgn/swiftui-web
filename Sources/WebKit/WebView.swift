// `WebView` and `WebPage` (sw-frameworks): the host's `<iframe>` over a white stand-in. The
// page object carries what to load (a URL, a request or inline HTML); the host loads it in
// the frame. Navigation state (title, progress, back and forward) is not reported back.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking   // Linux keeps URLRequest here
#endif
import SwiftUI
import Observation

/// The content a web view shows and how to load it.
@MainActor @Observable
public final class WebPage {
    public private(set) var url: URL?
    public private(set) var html: String?
    public var title: String { url?.host ?? "" }
    public var isLoading = false
    public var estimatedProgress: Double = 0
    public var backForwardList = BackForwardList()

    public struct BackForwardList: Sendable {
        public var backList: [URL] = []
        public var forwardList: [URL] = []
    }

    public struct NavigationID: Hashable, Sendable {
        let value: Int
    }

    public init() {}

    #if !os(WASI)   // WebFoundation has no URLRequest; wasm apps load URLs
    @discardableResult
    public func load(_ request: URLRequest) -> NavigationID? {
        url = request.url; html = nil
        return NavigationID(value: 1)
    }
    #endif

    @discardableResult
    public func load(_ url: URL) -> NavigationID? {
        self.url = url; html = nil
        return NavigationID(value: 1)
    }

    @discardableResult
    public func load(html: String, baseURL: URL? = nil) -> NavigationID? {
        self.html = html; url = baseURL
        return NavigationID(value: 1)
    }

    public func reload() {}
    public func stopLoading() { isLoading = false }
    public func goBack() {}
    public func goForward() {}
}

/// A view that displays web content.
public struct WebView: View {
    let page: WebPage?
    let url: URL?

    public init(url: URL?) {
        self.url = url
        page = nil
    }

    public init(_ page: WebPage) {
        self.page = page
        url = nil
    }

    public var body: some View {
        let kind: HostElement.Kind = page.map { .web(url: $0.url?.absoluteString, html: $0.html) } ?? .web(url: url?.absoluteString, html: nil)
        ZStack {
            Color.white
            _HostElementAnchor(kind: kind, identity: page.map { ObjectIdentifier($0) })
        }
        .clipped()
    }
}

extension View {
    /// Accepted; the hosts' frames keep their own scrolling and link handling.
    public func webViewScrollPosition(_ position: Binding<ScrollPosition>) -> some View { self }
    public func webViewContentBackground(_ visibility: Visibility) -> some View { self }
    public func webViewLinkPreviews(_ visibility: Visibility) -> some View { self }
    public func webViewMagnificationGestures(_ visibility: Visibility) -> some View { self }
    public func webViewBackForwardNavigationGestures(_ visibility: Visibility) -> some View { self }
}
