// Passkeys, security keys, saved passwords and Sign in with Apple for AuthenticationServices.
// `ASAuthorizationController` hands its requests to the browser's `navigator.credentials`
// (through AuthenticationServicesHost): a passkey or security-key registration is
// `credentials.create`, an assertion or a password request `credentials.get`, with the same
// relying party, challenge, user and preferences, and the credential the browser returns comes
// back as Apple's (its client data, attestation object, authenticator data and signature
// unchanged), so a server that verifies an iPhone's passkey verifies the browser's. WebAuthn
// only accepts a relying party that is the page's own site (or a suffix of it): another one
// fails as `.failed`, as it does on a phone without the associated domain. Sign in with Apple
// needs the developer's web service ID, which an app does not carry, so its requests end as
// `.notHandled`, and an Apple ID's state reads `.notFound`.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import AuthenticationServicesHost

// MARK: - Errors

/// The domain of `ASAuthorizationError`.
public let ASAuthorizationErrorDomain = "com.apple.AuthenticationServices.AuthorizationError"

/// Why an authorization ended without a credential.
public struct ASAuthorizationError: CustomNSError, Hashable, Sendable {
    public enum Code: Int, Hashable, Sendable {
        case unknown = 1000
        /// The person dismissed the request.
        case canceled = 1001
        case invalidResponse = 1002
        /// No provider could handle the request here.
        case notHandled = 1003
        case failed = 1004
        case notInteractive = 1005
        /// A registration matched a credential the request excluded.
        case matchedExcludedCredential = 1006
        case credentialImport = 1007
        case credentialExport = 1008
        case preferSignInWithApple = 1009
        case deviceNotConfiguredForPasskeyCreation = 1010
    }

    public let code: Code
    public init(_ code: Code, userInfo: [String: Any] = [:]) { self.code = code }

    public static var errorDomain: String { ASAuthorizationErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [:] }

    public static var unknown: Code { .unknown }
    public static var canceled: Code { .canceled }
    public static var invalidResponse: Code { .invalidResponse }
    public static var notHandled: Code { .notHandled }
    public static var failed: Code { .failed }
    public static var notInteractive: Code { .notInteractive }
    public static var matchedExcludedCredential: Code { .matchedExcludedCredential }
}

/// Lets `catch ASAuthorizationError.canceled` match the error.
public func ~= (code: ASAuthorizationError.Code, error: any Error) -> Bool {
    (error as? ASAuthorizationError)?.code == code
}

// MARK: - Authorizations, providers, requests and credentials

/// A source of credentials an authorization controller can ask.
public protocol ASAuthorizationProvider: NSObjectProtocol {}

/// What a successful authorization hands back.
public protocol ASAuthorizationCredential: NSObjectProtocol {}

/// A successful authorization: the provider that answered and its credential.
open class ASAuthorization: NSObject, @unchecked Sendable {
    public let provider: any ASAuthorizationProvider
    public let credential: any ASAuthorizationCredential

    package init(provider: any ASAuthorizationProvider, credential: any ASAuthorizationCredential) {
        self.provider = provider
        self.credential = credential
        super.init()
    }

    /// What an OpenID request asks to know about the person.
    public struct Scope: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let fullName = Scope(rawValue: "full_name")
        public static let email = Scope(rawValue: "email")
    }

    /// The OpenID operation a request performs.
    public struct OpenIDOperation: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let operationImplicit = OpenIDOperation(rawValue: "")
        public static let operationLogin = OpenIDOperation(rawValue: "login")
        public static let operationRefresh = OpenIDOperation(rawValue: "refresh")
        public static let operationLogout = OpenIDOperation(rawValue: "logout")
    }
}

/// A request for a credential from one provider.
open class ASAuthorizationRequest: NSObject, @unchecked Sendable {
    public let provider: any ASAuthorizationProvider
    package init(provider: any ASAuthorizationProvider) {
        self.provider = provider
        super.init()
    }
}

/// An OpenID request: the scopes, state and nonce it sends.
open class ASAuthorizationOpenIDRequest: ASAuthorizationRequest, @unchecked Sendable {
    open var requestedScopes: [ASAuthorization.Scope]?
    open var state: String?
    open var nonce: String?
    open var requestedOperation: ASAuthorization.OpenIDOperation = .operationLogin
}

/// Whether the person behind an Apple ID looks real.
public enum ASUserDetectionStatus: Int, Hashable, Sendable {
    case unsupported = 0
    case unknown = 1
    case likelyReal = 2
}

/// Whether the person is an adult, as Apple reports it.
public enum ASUserAgeRange: Int, Hashable, Sendable {
    case unknown = 0
    case child = 1
    case notChild = 2
}

// MARK: Sign in with Apple

/// Signs the person in with their Apple ID.
open class ASAuthorizationAppleIDProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    /// The state of an Apple ID's credential for this app.
    public enum CredentialState: Int, Hashable, Sendable {
        case revoked = 0
        case authorized = 1
        case notFound = 2
        case transferred = 3
    }

    /// Posted when the person stops using Sign in with Apple for the app.
    public static let credentialRevokedNotification = Notification.Name("ASAuthorizationAppleIDProviderCredentialRevokedNotification")

    public override init() { super.init() }

    open func createRequest() -> ASAuthorizationAppleIDRequest { ASAuthorizationAppleIDRequest(provider: self) }

    /// The state of `userID`'s credential: never authorized here, as Sign in with Apple does
    /// not run without the developer's web service.
    open func getCredentialState(forUserID userID: String,
                                 completion: @escaping (CredentialState, (any Error)?) -> Void) {
        completion(.notFound, nil)
    }

    open func credentialState(forUserID userID: String) async throws -> CredentialState { .notFound }
}

/// A request to sign in with an Apple ID.
open class ASAuthorizationAppleIDRequest: ASAuthorizationOpenIDRequest, @unchecked Sendable {
    /// The user identifier from an earlier sign-in, to refresh it.
    open var user: String?
}

/// The credential Sign in with Apple returns.
open class ASAuthorizationAppleIDCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    public let user: String
    public let state: String?
    public let authorizedScopes: [ASAuthorization.Scope]
    public let authorizationCode: Data?
    public let identityToken: Data?
    public let email: String?
    public let fullName: PersonNameComponents?
    public let realUserStatus: ASUserDetectionStatus
    public let userAgeRange: ASUserAgeRange

    package init(user: String, state: String? = nil, authorizedScopes: [ASAuthorization.Scope] = [],
                 authorizationCode: Data? = nil, identityToken: Data? = nil, email: String? = nil,
                 fullName: PersonNameComponents? = nil, realUserStatus: ASUserDetectionStatus = .unsupported) {
        self.user = user
        self.state = state
        self.authorizedScopes = authorizedScopes
        self.authorizationCode = authorizationCode
        self.identityToken = identityToken
        self.email = email
        self.fullName = fullName
        self.realUserStatus = realUserStatus
        userAgeRange = .unknown
        super.init()
    }
}

// MARK: Passwords

/// Fills in a password the browser has saved for the site.
open class ASAuthorizationPasswordProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    public override init() { super.init() }
    open func createRequest() -> ASAuthorizationPasswordRequest { ASAuthorizationPasswordRequest(provider: self) }
}

/// A request for a saved password.
open class ASAuthorizationPasswordRequest: ASAuthorizationRequest, @unchecked Sendable {}

/// A user name and password.
open class ASPasswordCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    public let user: String
    public let password: String
    public required init(user: String, password: String) {
        self.user = user
        self.password = password
        super.init()
    }
    public class func credential(withUser user: String, password: String) -> Self { self.init(user: user, password: password) }
}

// MARK: Public-key credentials (WebAuthn)

/// Whether the authenticator checks that it is the person (a fingerprint, a face, a PIN).
public struct ASAuthorizationPublicKeyCredentialUserVerificationPreference: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let preferred = Self(rawValue: "preferred")
    public static let required = Self(rawValue: "required")
    public static let discouraged = Self(rawValue: "discouraged")
}

/// The attestation a registration asks for.
public struct ASAuthorizationPublicKeyCredentialAttestationKind: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let none = Self(rawValue: "none")
    public static let direct = Self(rawValue: "direct")
    public static let indirect = Self(rawValue: "indirect")
    public static let enterprise = Self(rawValue: "enterprise")
}

/// Whether a registration asks for a discoverable credential.
public struct ASAuthorizationPublicKeyCredentialResidentKeyPreference: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let discouraged = Self(rawValue: "discouraged")
    public static let preferred = Self(rawValue: "preferred")
    public static let required = Self(rawValue: "required")
}

/// Where the authenticator that made a credential is.
public enum ASAuthorizationPublicKeyCredentialAttachment: Int, Hashable, Sendable {
    case platform = 0
    case crossPlatform = 1
}

/// A COSE algorithm a security key may sign with.
public struct ASCOSEAlgorithmIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static let ES256 = ASCOSEAlgorithmIdentifier(rawValue: -7)
}

/// An algorithm a registration accepts.
open class ASAuthorizationPublicKeyCredentialParameters: NSObject, @unchecked Sendable {
    public let algorithm: ASCOSEAlgorithmIdentifier
    public init(algorithm: ASCOSEAlgorithmIdentifier) {
        self.algorithm = algorithm
        super.init()
    }
}

/// A public-key credential.
public protocol ASPublicKeyCredential: ASAuthorizationCredential {
    var rawClientDataJSON: Data { get }
    var credentialID: Data { get }
}

/// A new public-key credential.
public protocol ASAuthorizationPublicKeyCredentialRegistration: ASPublicKeyCredential {
    var rawAttestationObject: Data? { get }
}

/// A signature from an existing public-key credential.
public protocol ASAuthorizationPublicKeyCredentialAssertion: ASPublicKeyCredential {
    var rawAuthenticatorData: Data! { get }
    var signature: Data! { get }
    var userID: Data! { get }
}

/// A credential a request names.
public protocol ASAuthorizationPublicKeyCredentialDescriptor: NSObjectProtocol {
    var credentialID: Data { get set }
}

/// A request to make a public-key credential.
public protocol ASAuthorizationPublicKeyCredentialRegistrationRequest: NSObjectProtocol {
    var relyingPartyIdentifier: String { get }
    var userID: Data { get set }
    var name: String { get set }
    var displayName: String? { get set }
    var challenge: Data { get set }
    var userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference { get set }
    var attestationPreference: ASAuthorizationPublicKeyCredentialAttestationKind { get set }
}

/// A request to sign with an existing public-key credential.
public protocol ASAuthorizationPublicKeyCredentialAssertionRequest: NSObjectProtocol {
    var challenge: Data { get set }
    var relyingPartyIdentifier: String { get set }
    var userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference { get set }
}

/// Passkeys: credentials on the device (or synced to it), through the browser's WebAuthn.
open class ASAuthorizationPlatformPublicKeyCredentialProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    public let relyingPartyIdentifier: String
    public init(relyingPartyIdentifier: String) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        super.init()
    }

    open func createCredentialRegistrationRequest(challenge: Data, name: String, userID: Data) -> ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest {
        ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest(provider: self, relyingPartyIdentifier: relyingPartyIdentifier, challenge: challenge, name: name, userID: userID)
    }

    open func createCredentialAssertionRequest(challenge: Data) -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {
        ASAuthorizationPlatformPublicKeyCredentialAssertionRequest(provider: self, relyingPartyIdentifier: relyingPartyIdentifier, challenge: challenge)
    }
}

/// A passkey a request names.
open class ASAuthorizationPlatformPublicKeyCredentialDescriptor: NSObject, ASAuthorizationPublicKeyCredentialDescriptor, @unchecked Sendable {
    open var credentialID: Data
    public init(credentialID: Data) {
        self.credentialID = credentialID
        super.init()
    }
}

/// A request to make a passkey.
open class ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest: ASAuthorizationRequest, ASAuthorizationPublicKeyCredentialRegistrationRequest, @unchecked Sendable {
    public let relyingPartyIdentifier: String
    open var userID: Data
    open var name: String
    open var displayName: String?
    open var challenge: Data
    open var userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference = .preferred
    open var attestationPreference: ASAuthorizationPublicKeyCredentialAttestationKind = .none
    /// Passkeys the person already has for this account: the browser refuses to make another.
    open var excludedCredentials: [ASAuthorizationPlatformPublicKeyCredentialDescriptor]?
    open var shouldShowHybridTransport = true

    init(provider: ASAuthorizationPlatformPublicKeyCredentialProvider, relyingPartyIdentifier: String, challenge: Data, name: String, userID: Data) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.challenge = challenge
        self.name = name
        self.userID = userID
        super.init(provider: provider)
    }
}

/// A request to sign in with a passkey.
open class ASAuthorizationPlatformPublicKeyCredentialAssertionRequest: ASAuthorizationRequest, ASAuthorizationPublicKeyCredentialAssertionRequest, @unchecked Sendable {
    open var challenge: Data
    open var relyingPartyIdentifier: String
    open var userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference = .preferred
    /// The passkeys that may answer; empty lets the person pick any of the site's.
    open var allowedCredentials: [ASAuthorizationPlatformPublicKeyCredentialDescriptor] = []
    open var shouldShowHybridTransport = true

    init(provider: ASAuthorizationPlatformPublicKeyCredentialProvider, relyingPartyIdentifier: String, challenge: Data) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.challenge = challenge
        super.init(provider: provider)
    }
}

/// A new passkey.
open class ASAuthorizationPlatformPublicKeyCredentialRegistration: NSObject, ASAuthorizationPublicKeyCredentialRegistration, @unchecked Sendable {
    public let credentialID: Data
    public let rawClientDataJSON: Data
    public let rawAttestationObject: Data?
    public let attachment: ASAuthorizationPublicKeyCredentialAttachment
    package init(credentialID: Data, rawClientDataJSON: Data, rawAttestationObject: Data?, attachment: ASAuthorizationPublicKeyCredentialAttachment) {
        self.credentialID = credentialID
        self.rawClientDataJSON = rawClientDataJSON
        self.rawAttestationObject = rawAttestationObject
        self.attachment = attachment
        super.init()
    }
}

/// A passkey's signature.
open class ASAuthorizationPlatformPublicKeyCredentialAssertion: NSObject, ASAuthorizationPublicKeyCredentialAssertion, @unchecked Sendable {
    public let credentialID: Data
    public let rawClientDataJSON: Data
    public let rawAuthenticatorData: Data!
    public let signature: Data!
    public let userID: Data!
    public let attachment: ASAuthorizationPublicKeyCredentialAttachment
    package init(credentialID: Data, rawClientDataJSON: Data, rawAuthenticatorData: Data, signature: Data, userID: Data, attachment: ASAuthorizationPublicKeyCredentialAttachment) {
        self.credentialID = credentialID
        self.rawClientDataJSON = rawClientDataJSON
        self.rawAuthenticatorData = rawAuthenticatorData
        self.signature = signature
        self.userID = userID
        self.attachment = attachment
        super.init()
    }
}

/// Security keys: credentials on a key over USB, NFC or Bluetooth, through WebAuthn.
open class ASAuthorizationSecurityKeyPublicKeyCredentialProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    public let relyingPartyIdentifier: String
    public init(relyingPartyIdentifier: String) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        super.init()
    }

    open func createCredentialRegistrationRequest(challenge: Data, displayName: String, name: String, userID: Data) -> ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest {
        let request = ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest(provider: self, relyingPartyIdentifier: relyingPartyIdentifier, challenge: challenge, name: name, userID: userID)
        request.displayName = displayName
        return request
    }

    open func createCredentialAssertionRequest(challenge: Data) -> ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest {
        ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest(provider: self, relyingPartyIdentifier: relyingPartyIdentifier, challenge: challenge)
    }
}

/// A security-key credential a request names, and how to reach its key.
open class ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor: NSObject, ASAuthorizationPublicKeyCredentialDescriptor, @unchecked Sendable {
    /// How a key connects.
    public struct Transport: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let usb = Transport(rawValue: "usb")
        public static let nfc = Transport(rawValue: "nfc")
        public static let bluetooth = Transport(rawValue: "ble")
        public static var allSupported: [Transport] { [.usb, .nfc, .bluetooth] }
    }

    open var credentialID: Data
    open var transports: [Transport]
    public init(credentialID: Data, transports allowedTransports: [Transport]) {
        self.credentialID = credentialID
        transports = allowedTransports
        super.init()
    }
}

/// A request to register a security key.
open class ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest: ASAuthorizationRequest, ASAuthorizationPublicKeyCredentialRegistrationRequest, @unchecked Sendable {
    public let relyingPartyIdentifier: String
    open var userID: Data
    open var name: String
    open var displayName: String?
    open var challenge: Data
    open var userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference = .preferred
    open var attestationPreference: ASAuthorizationPublicKeyCredentialAttestationKind = .none
    open var credentialParameters: [ASAuthorizationPublicKeyCredentialParameters] = [.init(algorithm: .ES256)]
    open var excludedCredentials: [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor]?
    open var residentKeyPreference: ASAuthorizationPublicKeyCredentialResidentKeyPreference = .preferred

    init(provider: ASAuthorizationSecurityKeyPublicKeyCredentialProvider, relyingPartyIdentifier: String, challenge: Data, name: String, userID: Data) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.challenge = challenge
        self.name = name
        self.userID = userID
        super.init(provider: provider)
    }
}

/// A request to sign in with a security key.
open class ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest: ASAuthorizationRequest, ASAuthorizationPublicKeyCredentialAssertionRequest, @unchecked Sendable {
    open var challenge: Data
    open var relyingPartyIdentifier: String
    open var userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference = .preferred
    open var allowedCredentials: [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor] = []

    init(provider: ASAuthorizationSecurityKeyPublicKeyCredentialProvider, relyingPartyIdentifier: String, challenge: Data) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.challenge = challenge
        super.init(provider: provider)
    }
}

/// A new security-key credential.
open class ASAuthorizationSecurityKeyPublicKeyCredentialRegistration: NSObject, ASAuthorizationPublicKeyCredentialRegistration, @unchecked Sendable {
    public let credentialID: Data
    public let rawClientDataJSON: Data
    public let rawAttestationObject: Data?
    public let transports: [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport]
    package init(credentialID: Data, rawClientDataJSON: Data, rawAttestationObject: Data?, transports: [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport]) {
        self.credentialID = credentialID
        self.rawClientDataJSON = rawClientDataJSON
        self.rawAttestationObject = rawAttestationObject
        self.transports = transports
        super.init()
    }
}

/// A security key's signature.
open class ASAuthorizationSecurityKeyPublicKeyCredentialAssertion: NSObject, ASAuthorizationPublicKeyCredentialAssertion, @unchecked Sendable {
    public let credentialID: Data
    public let rawClientDataJSON: Data
    public let rawAuthenticatorData: Data!
    public let signature: Data!
    public let userID: Data!
    package init(credentialID: Data, rawClientDataJSON: Data, rawAuthenticatorData: Data, signature: Data, userID: Data) {
        self.credentialID = credentialID
        self.rawClientDataJSON = rawClientDataJSON
        self.rawAuthenticatorData = rawAuthenticatorData
        self.signature = signature
        self.userID = userID
        super.init()
    }
}

// MARK: - The controller

/// What an authorization controller tells its delegate.
public protocol ASAuthorizationControllerDelegate: NSObjectProtocol {
    @MainActor func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization)
    @MainActor func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error)
}

extension ASAuthorizationControllerDelegate {
    @MainActor public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {}
    @MainActor public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {}
}

/// Provides the window an authorization controller presents from.
public protocol ASAuthorizationControllerPresentationContextProviding: NSObjectProtocol {
    @MainActor func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor
}

/// Asks the providers of its requests for a credential and tells its delegate what came back.
open class ASAuthorizationController: NSObject, @unchecked Sendable {
    /// How a controller presents its requests.
    public struct RequestOptions: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        /// Only credentials already on the device (the browser asks as usual).
        public static let preferImmediatelyAvailableCredentials = RequestOptions(rawValue: 1 << 0)
    }

    public let authorizationRequests: [ASAuthorizationRequest]
    open weak var delegate: (any ASAuthorizationControllerDelegate)?
    open weak var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)?

    private var abort: (() -> Void)?
    private var running = false

    public init(authorizationRequests: [ASAuthorizationRequest]) {
        self.authorizationRequests = authorizationRequests
        super.init()
    }

    open func performRequests() { perform(mediation: nil) }
    open func performRequests(options: RequestOptions) { perform(mediation: nil) }
    /// Offers the site's passkeys and passwords in the page's autofill.
    open func performAutoFillAssistedRequests() { perform(mediation: "conditional") }

    /// Withdraws the requests; the delegate gets `.canceled`.
    open func cancel() {
        guard running else { return }
        let abort = self.abort
        finish(.failure(ASAuthorizationError(.canceled)))
        abort?()
    }

    private func perform(mediation: String?) {
        guard !running else { return }
        guard let call = _ASCredentialCall(authorizationRequests, mediation: mediation),
              let credentials = _AuthenticationServicesHost.credentials else {
            deliver(.failure(ASAuthorizationError(.notHandled)))
            return
        }
        running = true
        weak let controller = self
        let abort = credentials(call.method, call.options) { result, errorName in
            controller?.finish(call.authorization(from: result, errorName: errorName))
        }
        if running { self.abort = abort } else { abort() }
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
        guard running else { return }
        running = false
        abort = nil
        deliver(result)
    }

    private func deliver(_ result: Result<ASAuthorization, any Error>) {
        let controller = self
        Task { @MainActor in
            switch result {
            case let .success(authorization): controller.delegate?.authorizationController(controller: controller, didCompleteWithAuthorization: authorization)
            case let .failure(error): controller.delegate?.authorizationController(controller: controller, didCompleteWithError: error)
            }
        }
    }
}

// MARK: - The browser call

/// One `navigator.credentials` call for a controller's requests: a registration creates (the
/// first one, as a phone makes one credential at a time); otherwise the assertions and the
/// password request share one `get`. Sign in with Apple requests alone make no call.
struct _ASCredentialCall {
    let method: String
    let options: String
    let registration: ASAuthorizationRequest?
    let passkeyAssertion: ASAuthorizationPlatformPublicKeyCredentialAssertionRequest?
    let keyAssertion: ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest?
    let password: ASAuthorizationPasswordRequest?

    init?(_ requests: [ASAuthorizationRequest], mediation: String?) {
        registration = requests.first { $0 is ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest || $0 is ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest }
        passkeyAssertion = requests.lazy.compactMap { $0 as? ASAuthorizationPlatformPublicKeyCredentialAssertionRequest }.first
        keyAssertion = requests.lazy.compactMap { $0 as? ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest }.first
        password = requests.lazy.compactMap { $0 as? ASAuthorizationPasswordRequest }.first
        var options: [String: Any] = [:]
        if let mediation { options["mediation"] = mediation }
        if let registration {
            method = "create"
            options["publicKey"] = Self.creation(registration)
        } else if passkeyAssertion != nil || keyAssertion != nil || password != nil {
            method = "get"
            let assertion: (any ASAuthorizationPublicKeyCredentialAssertionRequest)? = passkeyAssertion != nil ? passkeyAssertion : keyAssertion
            if let assertion {
                var allowed: [[String: Any]] = (passkeyAssertion?.allowedCredentials ?? []).map {
                    ["type": "public-key", "id": _base64URL($0.credentialID), "transports": ["internal", "hybrid"]] as [String: Any]
                }
                allowed += (keyAssertion?.allowedCredentials ?? []).map {
                    ["type": "public-key", "id": _base64URL($0.credentialID), "transports": $0.transports.map(\.rawValue)] as [String: Any]
                }
                var publicKey: [String: Any] = ["challenge": _base64URL(assertion.challenge), "rpId": assertion.relyingPartyIdentifier,
                                                "userVerification": assertion.userVerificationPreference.rawValue]
                if !allowed.isEmpty { publicKey["allowCredentials"] = allowed }
                options["publicKey"] = publicKey
            }
            if password != nil { options["password"] = true }
        } else {
            return nil
        }
        guard let json = try? JSONSerialization.data(withJSONObject: options), let text = String(data: json, encoding: .utf8) else { return nil }
        self.options = text
    }

    /// WebAuthn's `PublicKeyCredentialCreationOptionsJSON` for a registration.
    private static func creation(_ request: ASAuthorizationRequest) -> [String: Any] {
        guard let registration = request as? any ASAuthorizationPublicKeyCredentialRegistrationRequest else { return [:] }
        let key = request as? ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest
        let platform = request as? ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest
        let algorithms = key?.credentialParameters.map(\.algorithm.rawValue) ?? [-7, -257]
        var selection: [String: Any] = ["userVerification": registration.userVerificationPreference.rawValue,
                                        "authenticatorAttachment": key == nil ? "platform" : "cross-platform"]
        let resident = key?.residentKeyPreference.rawValue ?? "required"
        selection["residentKey"] = resident
        selection["requireResidentKey"] = resident == "required"
        var options: [String: Any] = [
            "rp": ["id": registration.relyingPartyIdentifier, "name": registration.relyingPartyIdentifier],
            "user": ["id": _base64URL(registration.userID), "name": registration.name, "displayName": registration.displayName ?? registration.name],
            "challenge": _base64URL(registration.challenge),
            "pubKeyCredParams": algorithms.map { ["type": "public-key", "alg": $0] as [String: Any] },
            "authenticatorSelection": selection,
            "attestation": registration.attestationPreference.rawValue,
        ]
        let excluded: [[String: Any]] = (platform?.excludedCredentials ?? []).map { ["type": "public-key", "id": _base64URL($0.credentialID)] as [String: Any] }
            + (key?.excludedCredentials ?? []).map { ["type": "public-key", "id": _base64URL($0.credentialID), "transports": $0.transports.map(\.rawValue)] as [String: Any] }
        if !excluded.isEmpty { options["excludeCredentials"] = excluded }
        return options
    }

    /// The authorization for what the browser returned, or the error it ended with.
    func authorization(from json: String?, errorName: String?) -> Result<ASAuthorization, any Error> {
        if let errorName { return .failure(ASAuthorizationError(Self.code(forDOMException: errorName))) }
        guard let json, let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(ASAuthorizationError(.canceled))
        }
        if object["type"] as? String == "password", let password {
            let credential = ASPasswordCredential(user: object["id"] as? String ?? "", password: object["password"] as? String ?? "")
            return .success(ASAuthorization(provider: password.provider, credential: credential))
        }
        guard let response = object["response"] as? [String: Any],
              let id = _data(base64URL: object["rawId"] as? String ?? object["id"] as? String),
              let clientData = _data(base64URL: response["clientDataJSON"] as? String) else {
            return .failure(ASAuthorizationError(.invalidResponse))
        }
        let attachment: ASAuthorizationPublicKeyCredentialAttachment = object["authenticatorAttachment"] as? String == "cross-platform" ? .crossPlatform : .platform
        if let registration {
            let attestation = _data(base64URL: response["attestationObject"] as? String)
            let credential: any ASAuthorizationCredential
            if registration is ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest {
                let transports = (response["transports"] as? [String] ?? []).map(ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.init(rawValue:))
                credential = ASAuthorizationSecurityKeyPublicKeyCredentialRegistration(credentialID: id, rawClientDataJSON: clientData, rawAttestationObject: attestation, transports: transports)
            } else {
                credential = ASAuthorizationPlatformPublicKeyCredentialRegistration(credentialID: id, rawClientDataJSON: clientData, rawAttestationObject: attestation, attachment: attachment)
            }
            return .success(ASAuthorization(provider: registration.provider, credential: credential))
        }
        guard let authenticatorData = _data(base64URL: response["authenticatorData"] as? String),
              let signature = _data(base64URL: response["signature"] as? String) else {
            return .failure(ASAuthorizationError(.invalidResponse))
        }
        let userID = _data(base64URL: response["userHandle"] as? String) ?? Data()
        // A security key answers as cross-platform; a passkey (here or on a phone nearby) as either.
        if let keyAssertion, attachment == .crossPlatform || passkeyAssertion == nil {
            let credential = ASAuthorizationSecurityKeyPublicKeyCredentialAssertion(credentialID: id, rawClientDataJSON: clientData, rawAuthenticatorData: authenticatorData, signature: signature, userID: userID)
            return .success(ASAuthorization(provider: keyAssertion.provider, credential: credential))
        }
        guard let passkeyAssertion else { return .failure(ASAuthorizationError(.invalidResponse)) }
        let credential = ASAuthorizationPlatformPublicKeyCredentialAssertion(credentialID: id, rawClientDataJSON: clientData, rawAuthenticatorData: authenticatorData, signature: signature, userID: userID, attachment: attachment)
        return .success(ASAuthorization(provider: passkeyAssertion.provider, credential: credential))
    }

    /// The authorization error for a `DOMException` WebAuthn rejects with.
    static func code(forDOMException name: String) -> ASAuthorizationError.Code {
        switch name {
        case "NotAllowedError", "AbortError": return .canceled
        case "InvalidStateError": return .matchedExcludedCredential
        case "NotSupportedError": return .notHandled
        default: return .failed
        }
    }
}

/// `data` as unpadded base64url, WebAuthn's JSON encoding of bytes.
func _base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// The bytes of base64url (padded or not).
func _data(base64URL text: String?) -> Data? {
    guard let text else { return nil }
    var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    return Data(base64Encoded: base64)
}
