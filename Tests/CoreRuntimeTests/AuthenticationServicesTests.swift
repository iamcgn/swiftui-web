// AuthenticationServices: web sign-in sessions through a stand-in window (GistHub's
// ASWebAuthenticationSession, IceCubes' and Thunderbird's webAuthenticationSession), passkey,
// security-key and password requests as the WebAuthn options the browser gets and the
// credentials it returns (Food Truck's AccountStore), and the Sign in with Apple button
// (Basic Car Maintenance's).
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import AuthenticationServices
import AuthenticationServicesHost

#if !os(WASI)
/// The window a stand-in host opened: the address it was given, the matcher, and the close.
@MainActor
private final class StandInWindow {
    var url: String?
    var matches: ((String) -> Bool)?
    var completion: ((String?) -> Void)?
    var closed = false

    func install() {
        _AuthenticationServicesHost.openSession = { url, matches, completion in
            MainActor.assumeIsolated {
                self.url = url
                self.matches = matches
                self.completion = completion
            }
            return { MainActor.assumeIsolated { self.closed = true } }
        }
    }

    /// The window reaches `address`; true when it was the callback (and the session ended).
    @discardableResult
    func reach(_ address: String) -> Bool {
        guard let matches, matches(address) else { return false }
        completion?(address)
        return true
    }

    func closeByHand() { completion?(nil) }
}

/// A stand-in for `navigator.credentials`: what it was asked, and its answer.
@MainActor
private final class StandInCredentials {
    var method: String?
    var options: [String: Any] = [:]
    var answer: (String?, String?) = (nil, "NotAllowedError")
    var aborted = false

    func install() {
        _AuthenticationServicesHost.credentials = { method, options, completion in
            MainActor.assumeIsolated {
                self.method = method
                self.options = (try? JSONSerialization.jsonObject(with: Data(options.utf8))) as? [String: Any] ?? [:]
                completion(self.answer.0, self.answer.1)
            }
            return { MainActor.assumeIsolated { self.aborted = true } }
        }
    }
}

private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    @MainActor func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { ASPresentationAnchor() }
}

/// base64url, as the browser's JSON carries bytes.
private func b64url(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func json(_ object: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
}

// Serialized: the tests share the host's hooks.
@Suite(.serialized) @MainActor struct WebAuthenticationSessionTests {
    init() {
        _AuthenticationServicesHost.openSession = nil
        _AuthenticationServicesHost.credentials = nil
    }

    @Test func aSessionCompletesWithTheCallbackAndClosesTheWindow() throws {
        let window = StandInWindow()
        window.install()
        var reached: [(URL?, (any Error)?)] = []
        let session = ASWebAuthenticationSession(url: URL(string: "https://github.com/login/oauth/authorize?client_id=1")!,
                                                 callbackURLScheme: "gisthub") { reached.append(($0, $1)) }
        let anchor = Anchor()
        session.presentationContextProvider = anchor
        #expect(session.canStart)
        #expect(session.start())
        #expect(!session.canStart)
        #expect(window.url == "https://github.com/login/oauth/authorize?client_id=1")
        // The sign-in page's own addresses are not the callback.
        #expect(!window.reach("https://github.com/session"))
        #expect(window.reach("gisthub://callback?code=abc"))
        #expect(reached.count == 1)
        #expect(reached[0].0?.absoluteString == "gisthub://callback?code=abc" && reached[0].1 == nil)
        // A second report changes nothing.
        window.completion?("gisthub://again")
        #expect(reached.count == 1)
    }

    @Test func anHTTPSCallbackMatchesItsHostAndPath() {
        let callback = ASWebAuthenticationSession.Callback.https(host: "example.com", path: "/auth/done")
        #expect(callback.matchesURL(URL(string: "https://example.com/auth/done?code=1")!))
        #expect(callback.matchesURL(URL(string: "https://EXAMPLE.com/auth/done/")!))
        #expect(!callback.matchesURL(URL(string: "https://example.com/auth/other")!))
        #expect(!callback.matchesURL(URL(string: "http://example.com/auth/done")!))
        #expect(ASWebAuthenticationSession.Callback.customScheme("myapp").matchesURL(URL(string: "MyApp://x")!))
    }

    @Test func closingTheWindowOrCancellingIsACancelledLogin() throws {
        let window = StandInWindow()
        window.install()
        var errors: [any Error] = []
        let anchor = Anchor()
        let first = ASWebAuthenticationSession(url: URL(string: "https://example.com/login")!, callbackURLScheme: "app") { _, error in
            if let error { errors.append(error) }
        }
        first.presentationContextProvider = anchor
        first.start()
        window.closeByHand()
        let second = ASWebAuthenticationSession(url: URL(string: "https://example.com/login")!, callbackURLScheme: "app") { _, error in
            if let error { errors.append(error) }
        }
        second.presentationContextProvider = anchor
        second.start()
        second.cancel()
        #expect(window.closed)
        #expect(errors.count == 2)
        #expect(errors.allSatisfy { ($0 as? ASWebAuthenticationSessionError)?.code == .canceledLogin })
        let caught: Bool
        do { throw errors[0] } catch ASWebAuthenticationSessionError.canceledLogin { caught = true } catch { caught = false }
        #expect(caught)
    }

    @Test func aSessionNeedsAPresentationContextAndABrowser() {
        var codes: [ASWebAuthenticationSessionError.Code] = []
        let session = ASWebAuthenticationSession(url: URL(string: "https://example.com")!, callbackURLScheme: "app") { _, error in
            codes.append((error as? ASWebAuthenticationSessionError)?.code ?? .canceledLogin)
        }
        #expect(!session.start())
        let anchor = Anchor()
        let headless = ASWebAuthenticationSession(url: URL(string: "https://example.com")!, callbackURLScheme: "app") { _, error in
            codes.append((error as? ASWebAuthenticationSessionError)?.code ?? .canceledLogin)
        }
        headless.presentationContextProvider = anchor
        #expect(!headless.canStart)
        #expect(!headless.start())
        #expect(codes == [.presentationContextNotProvided, .presentationContextInvalid])
    }

    @Test func swiftUIsSessionReturnsTheCallback() async throws {
        let window = StandInWindow()
        window.install()
        let session = EnvironmentValues().webAuthenticationSession
        async let url = session.authenticate(using: URL(string: "https://mastodon.social/oauth/authorize")!, callbackURLScheme: "icecubesapp")
        for _ in 0..<100 where window.completion == nil { await Task.yield() }
        window.reach("icecubesapp://?code=xyz")
        let reached = try await url
        #expect(reached.absoluteString == "icecubesapp://?code=xyz")

        async let refused = session.authenticate(using: URL(string: "https://login.example.com")!,
                                                 callback: .customScheme("tb"), additionalHeaderFields: [:])
        for _ in 0..<100 where window.url != "https://login.example.com" { await Task.yield() }
        window.closeByHand()
        do {
            _ = try await refused
            Issue.record("closing the window did not throw")
        } catch let error as ASWebAuthenticationSessionError {
            #expect(error.code == .canceledLogin)
        }
    }

    // MARK: Authorization

    @Test func aPasskeyRegistrationCreatesWithTheRequestsOptions() async throws {
        let browser = StandInCredentials()
        browser.install()
        browser.answer = (json(["type": "public-key", "id": b64url([1, 2, 3]), "rawId": b64url([1, 2, 3]), "authenticatorAttachment": "platform",
                                "response": ["clientDataJSON": b64url([9, 9]), "attestationObject": b64url([7, 7, 7])]]), nil)
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
        let request = provider.createCredentialRegistrationRequest(challenge: Data([0xFB, 0xFF]), name: "sam", userID: Data("sam".utf8))
        request.excludedCredentials = [ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: Data([5]))]
        let result = try await EnvironmentValues().authorizationController.performRequests([request])
        #expect(browser.method == "create")
        let options = try #require(browser.options["publicKey"] as? [String: Any])
        #expect((options["rp"] as? [String: Any])?["id"] as? String == "example.com")
        #expect(options["challenge"] as? String == "-_8")
        let user = try #require(options["user"] as? [String: Any])
        #expect(user["id"] as? String == b64url(Array("sam".utf8)) && user["name"] as? String == "sam")
        #expect((options["authenticatorSelection"] as? [String: Any])?["authenticatorAttachment"] as? String == "platform")
        #expect((options["excludeCredentials"] as? [[String: Any]])?.first?["id"] as? String == b64url([5]))
        guard case let .passkeyRegistration(registration) = result else { Issue.record("not a registration"); return }
        #expect(registration.credentialID == Data([1, 2, 3]))
        #expect(registration.rawClientDataJSON == Data([9, 9]))
        #expect(registration.rawAttestationObject == Data([7, 7, 7]))
        #expect(registration.attachment == .platform)
    }

    @Test func signingInAsksForPasskeysAndPasswordsTogether() async throws {
        let browser = StandInCredentials()
        browser.install()
        let passkeys = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
        let requests = [passkeys.createCredentialAssertionRequest(challenge: Data("challenge".utf8)), ASAuthorizationPasswordProvider().createRequest()]
        browser.answer = (json(["type": "password", "id": "sam", "password": "hunter2"]), nil)
        let saved = try await EnvironmentValues().authorizationController.performRequests(requests)
        #expect(browser.method == "get")
        #expect(browser.options["password"] as? Bool == true)
        let publicKey = try #require(browser.options["publicKey"] as? [String: Any])
        #expect(publicKey["rpId"] as? String == "example.com" && publicKey["challenge"] as? String == b64url(Array("challenge".utf8)))
        #expect(publicKey["allowCredentials"] == nil)
        guard case let .password(password) = saved else { Issue.record("not a password"); return }
        #expect(password.user == "sam" && password.password == "hunter2")

        browser.answer = (json(["type": "public-key", "id": b64url([4]), "rawId": b64url([4]), "authenticatorAttachment": "platform",
                                "response": ["clientDataJSON": b64url([1]), "authenticatorData": b64url([2]), "signature": b64url([3]),
                                             "userHandle": b64url(Array("sam".utf8))]]), nil)
        let signedIn = try await EnvironmentValues().authorizationController.performRequests(requests)
        guard case let .passkeyAssertion(assertion) = signedIn else { Issue.record("not an assertion"); return }
        #expect(String(bytes: assertion.userID, encoding: .utf8) == "sam")
        #expect(assertion.rawAuthenticatorData == Data([2]) && assertion.signature == Data([3]) && assertion.credentialID == Data([4]))
    }

    @Test func aSecurityKeyAssertionNamesItsKeysTransports() async throws {
        let browser = StandInCredentials()
        browser.install()
        let keys = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
        let request = keys.createCredentialAssertionRequest(challenge: Data([1]))
        request.allowedCredentials = [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(credentialID: Data([8]), transports: [.usb, .nfc])]
        browser.answer = (json(["type": "public-key", "id": b64url([8]), "rawId": b64url([8]), "authenticatorAttachment": "cross-platform",
                                "response": ["clientDataJSON": b64url([1]), "authenticatorData": b64url([2]), "signature": b64url([3]), "userHandle": NSNull()]]), nil)
        let result = try await EnvironmentValues().authorizationController.performRequest(request)
        let allowed = try #require((browser.options["publicKey"] as? [String: Any])?["allowCredentials"] as? [[String: Any]])
        #expect(allowed.first?["transports"] as? [String] == ["usb", "nfc"])
        guard case let .securityKeyAssertion(assertion) = result else { Issue.record("not a key assertion"); return }
        #expect(assertion.credentialID == Data([8]) && assertion.userID == Data())
    }

    @Test func aPhonesPasskeyAnsweringBothKindsIsAPasskey() async throws {
        let browser = StandInCredentials()
        browser.install()
        let passkeys = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
        let keys = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
        let requests: [ASAuthorizationRequest] = [passkeys.createCredentialAssertionRequest(challenge: Data([1])),
                                                  keys.createCredentialAssertionRequest(challenge: Data([1]))]
        // 32 bytes of relying party hash, then the flags: 0x1D is user present and verified,
        // backup eligible and backed up (a synced passkey); 0x05 is a key's present and verified.
        func answer(flags: UInt8) -> String {
            json(["type": "public-key", "id": b64url([9]), "rawId": b64url([9]), "authenticatorAttachment": "cross-platform",
                  "response": ["clientDataJSON": b64url([1]), "authenticatorData": b64url(Array(repeating: 0, count: 32) + [flags, 0, 0, 0, 1]),
                               "signature": b64url([3]), "userHandle": b64url([7])]])
        }
        browser.answer = (answer(flags: 0x1D), nil)
        let phone = try await EnvironmentValues().authorizationController.performRequests(requests)
        guard case let .passkeyAssertion(passkey) = phone else { Issue.record("not a passkey"); return }
        #expect(passkey.attachment == .crossPlatform && passkey.credentialID == Data([9]))

        browser.answer = (answer(flags: 0x05), nil)
        let key = try await EnvironmentValues().authorizationController.performRequests(requests)
        guard case .securityKeyAssertion = key else { Issue.record("not a key assertion"); return }
    }

    @Test func theBrowsersRefusalsBecomeAuthorizationErrors() async throws {
        let browser = StandInCredentials()
        browser.install()
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
        let request = provider.createCredentialAssertionRequest(challenge: Data([1]))
        for (name, code) in [("NotAllowedError", ASAuthorizationError.Code.canceled), ("InvalidStateError", .matchedExcludedCredential),
                             ("SecurityError", .failed), ("NotSupportedError", .notHandled)] {
            browser.answer = (nil, name)
            do {
                _ = try await EnvironmentValues().authorizationController.performRequest(request)
                Issue.record("\(name) did not throw")
            } catch let error as ASAuthorizationError {
                #expect(error.code == code)
            }
        }
        // Sign in with Apple has no browser call: its requests are not handled here.
        browser.method = nil
        await #expect(throws: ASAuthorizationError.self) {
            _ = try await EnvironmentValues().authorizationController.performRequest(ASAuthorizationAppleIDProvider().createRequest())
        }
        #expect(browser.method == nil)
        #expect(try await ASAuthorizationAppleIDProvider().credentialState(forUserID: "001") == .notFound)
    }

    @Test func aControllerTellsItsDelegate() async throws {
        let browser = StandInCredentials()
        browser.install()
        browser.answer = (json(["type": "password", "id": "kim", "password": "pw"]), nil)
        final class Delegate: NSObject, ASAuthorizationControllerDelegate {
            var authorizations: [ASAuthorization] = []
            func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
                authorizations.append(authorization)
            }
        }
        let delegate = Delegate()
        let passwords = ASAuthorizationPasswordProvider()
        let controller = ASAuthorizationController(authorizationRequests: [passwords.createRequest()])
        controller.delegate = delegate
        controller.performRequests()
        for _ in 0..<100 where delegate.authorizations.isEmpty { await Task.yield() }
        let authorization = try #require(delegate.authorizations.first)
        #expect(authorization.provider === passwords)
        #expect((authorization.credential as? ASPasswordCredential)?.user == "kim")
    }

    @Test func theSignInWithAppleButtonReportsNotHandled() async throws {
        var requested = false
        var outcome: Result<ASAuthorization, any Error>?
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.email]
            requested = true
        } onCompletion: { outcome = $0 }
            .signInWithAppleButtonStyle(.whiteOutline)
            .frame(height: 50))
        runtime.layout(in: CGSize(width: 320, height: 480))
        _ = runtime.render(scale: 2)
        let button = try #require(runtime.semanticsTree().first { $0.label == "Continue with Apple" })
        runtime.activate(semanticsIdentifier: button.identifier)
        #expect(requested)
        guard case let .failure(error) = outcome else { Issue.record("no failure"); return }
        #expect((error as? ASAuthorizationError)?.code == .notHandled)
    }
}
#endif
