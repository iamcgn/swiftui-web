// The browser behind AuthenticationServices: a sign-in window for `ASWebAuthenticationSession`
// and `navigator.credentials` (WebAuthn passkeys and saved passwords) for
// `ASAuthorizationController`. SwiftUIWebCanvas installs the hooks (AuthenticationHost.swift);
// a module of its own, depending on nothing, so installing them links only this into an app
// that never signs in (decision 0006).

public enum _AuthenticationServicesHost {
    /// Opens `url` in a sign-in window. `matches` says whether an address the window reached is
    /// the app's callback; `completion` gets that address, or nil when the window closed (or
    /// never opened) first. Returns what closes the window.
    nonisolated(unsafe) public static var openSession: ((_ url: String, _ matches: @escaping (String) -> Bool,
                                                        _ completion: @escaping (String?) -> Void) -> () -> Void)?

    /// `navigator.credentials.create` (`method` "create") or `.get` ("get") with options as
    /// WebAuthn's JSON forms (binary fields base64url), plus `"password": true` for a saved
    /// password and `"mediation"`. `completion(result, errorName)`: the credential as JSON
    /// (`{"type": "password", "id", "password"}`, or a public-key credential's JSON form), or the
    /// DOMException's name. Returns what aborts the request.
    nonisolated(unsafe) public static var credentials: ((_ method: String, _ options: String,
                                                        _ completion: @escaping (String?, String?) -> Void) -> () -> Void)?
}
