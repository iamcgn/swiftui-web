// AuthenticationServices' SwiftUI side: the `authorizationController` environment value (async
// passkey and password requests), `ASAuthorizationResult`, and `SignInWithAppleButton`, which
// draws Apple's button (the black, white or outlined capsule with its title) and reports, as
// every Sign in with Apple request does here, `.notHandled`.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

// MARK: - Results

/// The credential an authorization controller's async requests return, by kind.
public enum ASAuthorizationResult: @unchecked Sendable {
    case appleID(ASAuthorizationAppleIDCredential)
    case password(ASPasswordCredential)
    case passkeyAssertion(ASAuthorizationPlatformPublicKeyCredentialAssertion)
    case passkeyRegistration(ASAuthorizationPlatformPublicKeyCredentialRegistration)
    case securityKeyAssertion(ASAuthorizationSecurityKeyPublicKeyCredentialAssertion)
    case securityKeyRegistration(ASAuthorizationSecurityKeyPublicKeyCredentialRegistration)

    package init?(_ authorization: ASAuthorization) {
        switch authorization.credential {
        case let credential as ASAuthorizationAppleIDCredential: self = .appleID(credential)
        case let credential as ASPasswordCredential: self = .password(credential)
        case let credential as ASAuthorizationPlatformPublicKeyCredentialAssertion: self = .passkeyAssertion(credential)
        case let credential as ASAuthorizationPlatformPublicKeyCredentialRegistration: self = .passkeyRegistration(credential)
        case let credential as ASAuthorizationSecurityKeyPublicKeyCredentialAssertion: self = .securityKeyAssertion(credential)
        case let credential as ASAuthorizationSecurityKeyPublicKeyCredentialRegistration: self = .securityKeyRegistration(credential)
        default: return nil
        }
    }
}

// MARK: - The SwiftUI controller

/// Performs authorization requests from a SwiftUI view:
/// `@Environment(\.authorizationController)`, then `try await performRequests(…)`.
@MainActor
public struct AuthorizationController {
    nonisolated init() {}

    /// Asks for a credential from `requests` and returns it; throws `ASAuthorizationError`.
    public func performRequests(_ requests: [ASAuthorizationRequest],
                                options: ASAuthorizationController.RequestOptions = []) async throws -> ASAuthorizationResult {
        try await run(requests) { $0.performRequests(options: options) }
    }

    public func performRequest(_ request: ASAuthorizationRequest,
                               options: ASAuthorizationController.RequestOptions = []) async throws -> ASAuthorizationResult {
        try await performRequests([request], options: options)
    }

    /// Offers `requests` in the page's autofill.
    public func performAutoFillAssistedRequests(_ requests: [ASAuthorizationRequest]) async throws -> ASAuthorizationResult {
        try await run(requests) { $0.performAutoFillAssistedRequests() }
    }

    public func performAutoFillAssistedRequest(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationResult {
        try await performAutoFillAssistedRequests([request])
    }

    private func run(_ requests: [ASAuthorizationRequest], _ start: (ASAuthorizationController) -> Void) async throws -> ASAuthorizationResult {
        let controller = ASAuthorizationController(authorizationRequests: requests)
        let relay = _AuthorizationRelay()
        controller.delegate = relay
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorizationResult, any Error>) in
                relay.continuation = continuation
                relay.controller = controller
                start(controller)
            }
        } onCancel: {
            controller.cancel()
        }
    }
}

/// Hands a controller's answer to the waiting task (and keeps the controller alive meanwhile).
final class _AuthorizationRelay: NSObject, ASAuthorizationControllerDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<ASAuthorizationResult, any Error>?
    var controller: ASAuthorizationController?

    @MainActor func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let result = ASAuthorizationResult(authorization) {
            resume(.success(result))
        } else {
            resume(.failure(ASAuthorizationError(.invalidResponse)))
        }
    }

    @MainActor func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<ASAuthorizationResult, any Error>) {
        let continuation = self.continuation
        self.continuation = nil
        controller = nil
        continuation?.resume(with: result)
    }
}

private struct AuthorizationControllerKey: EnvironmentKey {
    static let defaultValue = AuthorizationController()
}

extension EnvironmentValues {
    /// Performs passkey, security-key, password and Sign in with Apple requests.
    public var authorizationController: AuthorizationController { self[AuthorizationControllerKey.self] }
}

// MARK: - Sign in with Apple

/// Apple's Sign in with Apple button. Pressing it hands the app an Apple ID request to fill in
/// (`onRequest`) and then reports the outcome (`onCompletion`): `.notHandled`, as Sign in with
/// Apple needs the developer's web service ID, which the app does not carry.
public struct SignInWithAppleButton: View {
    /// The button's title.
    public struct Label: Hashable, Sendable {
        let title: String
        /// "Sign in with Apple".
        public static let signIn = Label(title: "Sign in with Apple")
        /// "Continue with Apple".
        public static let `continue` = Label(title: "Continue with Apple")
        /// "Sign up with Apple".
        public static let signUp = Label(title: "Sign up with Apple")
    }

    /// The button's colours.
    public struct Style: Hashable, Sendable {
        let kind: Int
        /// White on black.
        public static let black = Style(kind: 0)
        /// Black on white, for dark backgrounds.
        public static let white = Style(kind: 1)
        /// Black on white with a black outline, for light backgrounds.
        public static let whiteOutline = Style(kind: 2)
    }

    let label: Label
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, any Error>) -> Void
    @Environment(\._signInWithAppleButtonStyle) private var style

    public init(_ label: Label = .signIn, onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
                onCompletion: @escaping (Result<ASAuthorization, any Error>) -> Void) {
        self.label = label
        self.onRequest = onRequest
        self.onCompletion = onCompletion
    }

    public var body: some View {
        let dark = style == .black
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            onRequest(request)
            onCompletion(.failure(ASAuthorizationError(.notHandled)))
        } label: {
            Text(label.title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(dark ? Color.white : Color.black)
                .lineLimit(1)
                .frame(minWidth: 140, maxWidth: .infinity, minHeight: 30, idealHeight: 44, maxHeight: 64)
                .background(shape.fill(dark ? Color.black : Color.white))
                .overlay(shape.stroke(Color.black, lineWidth: style == .whiteOutline ? 1 : 0))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label.title))
    }
}

private struct SignInWithAppleButtonStyleKey: EnvironmentKey {
    static let defaultValue = SignInWithAppleButton.Style.black
}

extension EnvironmentValues {
    var _signInWithAppleButtonStyle: SignInWithAppleButton.Style {
        get { self[SignInWithAppleButtonStyleKey.self] }
        set { self[SignInWithAppleButtonStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the colours of the Sign in with Apple buttons in this view.
    nonisolated public func signInWithAppleButtonStyle(_ style: SignInWithAppleButton.Style) -> some View {
        environment(\._signInWithAppleButtonStyle, style)
    }
}
