// Web sign-in for AuthenticationServices: `ASWebAuthenticationSession` and SwiftUI's
// `WebAuthenticationSession` (`@Environment(\.webAuthenticationSession)`). The browser host
// (AuthenticationServicesHost) opens the sign-in page in a window of its own and watches the
// address it reaches: once it is the app's callback, the window closes and the session
// completes with that address; closing the window cancels. The page can only read the window's
// address once it is back on the page's own origin, so an `.https(host:path:)` callback on the
// app's own site completes, while a custom scheme (`myapp://`), which a browser cannot hand
// back to a page, ends as a cancelled sign-in when the window is closed. The browser shares
// its cookies with every window, so an ephemeral session is not private here, and a window
// cannot be opened with extra header fields, so `additionalHeaderFields` is kept, not sent.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI            // UIWindow, the presentation anchor
import AuthenticationServicesHost

/// The window a session or an authorization controller presents its interface in.
public typealias ASPresentationAnchor = UIWindow

/// The domain of `ASWebAuthenticationSessionError`.
public let ASWebAuthenticationSessionErrorDomain = "com.apple.AuthenticationServices.WebAuthenticationSession"

/// Why a web authentication session ended without a callback.
public struct ASWebAuthenticationSessionError: CustomNSError, Hashable, Sendable {
    public enum Code: Int, Hashable, Sendable {
        /// The person closed the sign-in window, or the session was cancelled.
        case canceledLogin = 1
        /// No presentation context provider was set before `start()`.
        case presentationContextNotProvided = 2
        /// There is no window to present in.
        case presentationContextInvalid = 3
    }

    public let code: Code
    public init(_ code: Code, userInfo: [String: Any] = [:]) { self.code = code }

    public static var errorDomain: String { ASWebAuthenticationSessionErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [:] }

    public static var canceledLogin: Code { .canceledLogin }
    public static var presentationContextNotProvided: Code { .presentationContextNotProvided }
    public static var presentationContextInvalid: Code { .presentationContextInvalid }

    public static func ~= (code: Code, error: any Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == code
    }
}

/// Provides the window a web authentication session presents its sign-in page from.
public protocol ASWebAuthenticationPresentationContextProviding: NSObjectProtocol {
    @MainActor func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
}

/// A session that signs the person in through a web page and hands back the callback address.
open class ASWebAuthenticationSession: NSObject, @unchecked Sendable {
    public typealias CompletionHandler = (URL?, (any Error)?) -> Void

    /// The address that ends a session: a custom scheme, or an https host and path.
    public struct Callback: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case scheme(String)
            case https(host: String, path: String)
        }
        let kind: Kind

        /// Any address in `customScheme` (without "://").
        public static func customScheme(_ customScheme: String) -> Callback { Callback(kind: .scheme(customScheme)) }
        /// An https address on `host` at `path`.
        public static func https(host: String, path: String) -> Callback { Callback(kind: .https(host: host, path: path)) }

        /// Whether `url` is this callback.
        public func matchesURL(_ url: URL) -> Bool {
            switch kind {
            case let .scheme(scheme):
                return url.scheme?.lowercased() == scheme.lowercased()
            case let .https(host, path):
                return url.scheme?.lowercased() == "https" && url.host?.lowercased() == host.lowercased()
                    && Self.normalized(url.path) == Self.normalized(path)
            }
        }

        private static func normalized(_ path: String) -> String {
            let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
            return trimmed.isEmpty ? "/" : trimmed
        }
    }

    public let url: URL
    public let callback: Callback?
    private var completionHandler: CompletionHandler?
    /// Provides the window the sign-in page opens from; `start()` needs one.
    open weak var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
    /// Asks for a session that shares no cookies with the browser (the browser's windows share
    /// them all, so this is kept, not honoured).
    open var prefersEphemeralWebBrowserSession = false
    /// Header fields for the first request (a window cannot be opened with them; kept, not sent).
    open var additionalHeaderFields: [String: String]?

    private var started = false
    private var finished = false
    private var close: (() -> Void)?

    public init(url URL: URL, callbackURLScheme: String?, completionHandler: @escaping CompletionHandler) {
        url = URL
        callback = callbackURLScheme.map { .customScheme($0) }
        self.completionHandler = completionHandler
        super.init()
    }

    public init(url URL: URL, callback: Callback, completionHandler: @escaping CompletionHandler) {
        url = URL
        self.callback = callback
        self.completionHandler = completionHandler
        super.init()
    }

    /// Whether `start()` would open the sign-in window: there is a browser to open it in and
    /// the session has not started.
    open var canStart: Bool { !started && _AuthenticationServicesHost.openSession != nil }

    /// Opens the sign-in page. False (and the completion handler called with the reason) when
    /// there is no presentation context provider or no browser window to open it in.
    @discardableResult
    open func start() -> Bool {
        guard !started else { return false }
        guard presentationContextProvider != nil else {
            finish(nil, ASWebAuthenticationSessionError(.presentationContextNotProvided))
            return false
        }
        guard let open = _AuthenticationServicesHost.openSession else {
            finish(nil, ASWebAuthenticationSessionError(.presentationContextInvalid))
            return false
        }
        started = true
        let callback = callback
        nonisolated(unsafe) weak let session = self
        let close = open(url.absoluteString, { address in
            guard let reached = URL(string: address) else { return false }
            guard let callback else { return reached.scheme.map { !["http", "https", "about"].contains($0.lowercased()) } ?? false }
            return callback.matchesURL(reached)
        }, { address in
            guard let session else { return }
            if let address, let reached = URL(string: address) {
                session.finish(reached, nil)
            } else {
                session.finish(nil, ASWebAuthenticationSessionError(.canceledLogin))
            }
        })
        if finished { close() } else { self.close = close }
        return true
    }

    /// Closes the sign-in window; the completion handler gets `canceledLogin`.
    open func cancel() {
        guard started, !finished else { return }
        let close = self.close
        finish(nil, ASWebAuthenticationSessionError(.canceledLogin))
        close?()
    }

    private func finish(_ url: URL?, _ error: (any Error)?) {
        guard !finished else { return }
        finished = true
        close = nil
        let handler = completionHandler
        completionHandler = nil
        handler?(url, error)
    }
}

// MARK: - SwiftUI

/// Signs the person in through a web page from a SwiftUI view:
/// `@Environment(\.webAuthenticationSession)`, then `try await authenticate(using:…)`.
@MainActor
public struct WebAuthenticationSession {
    /// The browser session a sign-in prefers.
    public struct BrowserSession: Hashable, Sendable {
        let ephemeral: Bool
        /// A session that shares no cookies (here the browser's windows share them all).
        public static let ephemeral = BrowserSession(ephemeral: true)
        /// The browser's own session.
        public static let shared = BrowserSession(ephemeral: false)
    }

    nonisolated init() {}

    /// Opens `url` and returns the address that reached `callbackURLScheme`; throws
    /// `ASWebAuthenticationSessionError.canceledLogin` when the person closes the window.
    public func authenticate(using url: URL, callbackURLScheme: String,
                             preferredBrowserSession: BrowserSession? = nil) async throws -> URL {
        try await authenticate(using: url, callback: .customScheme(callbackURLScheme),
                               preferredBrowserSession: preferredBrowserSession, additionalHeaderFields: [:])
    }

    /// Opens `url` and returns the address that matched `callback`.
    public func authenticate(using url: URL, callback: ASWebAuthenticationSession.Callback,
                             preferredBrowserSession: BrowserSession? = nil,
                             additionalHeaderFields: [String: String]) async throws -> URL {
        let anchor = _SessionAnchor()
        let holder = _SessionHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                let session = ASWebAuthenticationSession(url: url, callback: callback) { url, error in
                    if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin)) }
                }
                session.presentationContextProvider = anchor
                session.prefersEphemeralWebBrowserSession = preferredBrowserSession?.ephemeral ?? false
                session.additionalHeaderFields = additionalHeaderFields
                holder.session = session
                session.start()
            }
        } onCancel: {
            Task { @MainActor in holder.session?.cancel() }
        }
    }
}

/// The presentation context `WebAuthenticationSession` gives its session.
final class _SessionAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    @MainActor func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { ASPresentationAnchor() }
}

/// Holds a running session so that cancelling the task can close its window.
final class _SessionHolder: @unchecked Sendable {
    var session: ASWebAuthenticationSession?
}

private struct WebAuthenticationSessionKey: EnvironmentKey {
    static let defaultValue = WebAuthenticationSession()
}

extension EnvironmentValues {
    /// Signs the person in through a web page.
    public var webAuthenticationSession: WebAuthenticationSession { self[WebAuthenticationSessionKey.self] }
}
