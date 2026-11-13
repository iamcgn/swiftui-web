// The browser behind AuthenticationServices: a sign-in window for `ASWebAuthenticationSession`
// (`window.open`, its address read every quarter second once it is back on the page's origin,
// the window closed when that address is the app's callback) and `navigator.credentials` for
// passkeys, security keys and saved passwords, with WebAuthn's JSON options turned into the
// buffers the API takes and its credential back into JSON.
#if os(WASI)
import AuthenticationServicesHost
import JavaScriptKit

@MainActor
enum AuthenticationHost {
    static func install() {
        _AuthenticationServicesHost.openSession = { url, matches, completion in openSession(url, matches, completion) }
        _AuthenticationServicesHost.credentials = { method, options, completion in credentials(method, options, completion) }
    }

    nonisolated(unsafe) static var retained: [JSClosure] = []

    /// `(url, report)` → the close function: opens the window and calls `report(address)` with
    /// each same-origin address it reaches, and `report(null)` once when it closes (or never
    /// opened). `report` returns true to end the session, which closes the window.
    private static let session: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var w = window.open(url, '_blank', 'popup,width=520,height=680');
        var done = false;
        var end = function () { if (done) return; done = true; clearInterval(timer); try { if (w && !w.closed) w.close(); } catch (e) {} };
        if (!w) { setTimeout(function () { report(null); }, 0); return function () {}; }
        var timer = setInterval(function () {
          var closed = true; try { closed = w.closed; } catch (e) {}
          if (closed) { end(); report(null); return; }
          var href = null; try { href = w.location.href; } catch (e) {}
          if (href && href !== 'about:blank' && report(href) === true) { end(); }
        }, 250);
        return end;
        """
        return try? make.throws.new("url", "report", body)
    }()

    /// `(method, optionsJSON, done)` → the abort function: `navigator.credentials[method]`
    /// with the options' base64url fields as buffers; `done(json, null)` or `done(null, name)`.
    private static let call: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var c = navigator.credentials;
        if (!c || !c[method]) { setTimeout(function () { done(null, 'NotSupportedError'); }, 0); return function () {}; }
        var buf = function (s) { s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '=';
          var b = atob(s), u = new Uint8Array(b.length); for (var i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u.buffer; };
        var str = function (v) { if (!v) return null; var u = new Uint8Array(v), b = '';
          for (var i = 0; i < u.length; i++) b += String.fromCharCode(u[i]);
          return btoa(b).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, ''); };
        var o = JSON.parse(options), k = o.publicKey;
        if (k) {
          k.challenge = buf(k.challenge);
          if (k.user) k.user.id = buf(k.user.id);
          (k.allowCredentials || []).concat(k.excludeCredentials || []).forEach(function (d) { d.id = buf(d.id); });
        }
        var abort = window.AbortController ? new AbortController() : null;
        if (abort) o.signal = abort.signal;
        c[method](o).then(function (r) {
          if (!r) { done(null, 'NotAllowedError'); return; }
          if (r.type === 'password') { done(JSON.stringify({ type: 'password', id: r.id, password: r.password }), null); return; }
          var p = r.response, j = { type: r.type, id: r.id, rawId: str(r.rawId), authenticatorAttachment: r.authenticatorAttachment,
            response: { clientDataJSON: str(p.clientDataJSON) } };
          if (p.attestationObject) { j.response.attestationObject = str(p.attestationObject);
            if (p.getTransports) j.response.transports = p.getTransports(); }
          if (p.authenticatorData) { j.response.authenticatorData = str(p.authenticatorData);
            j.response.signature = str(p.signature); j.response.userHandle = str(p.userHandle); }
          done(JSON.stringify(j), null);
        }, function (e) { done(null, (e && e.name) || 'UnknownError'); });
        return function () { if (abort) abort.abort(); };
        """
        return try? make.throws.new("method", "options", "done", body)
    }()

    private static func openSession(_ url: String, _ matches: @escaping (String) -> Bool,
                                    _ completion: @escaping (String?) -> Void) -> () -> Void {
        guard let session else {
            completion(nil)
            return {}
        }
        var finished = false
        let report = JSClosure { (arguments: [JSValue]) -> JSValue in
            guard !finished else { return .boolean(false) }
            guard let address = arguments.first?.string else {
                finished = true
                completion(nil)
                return .boolean(false)
            }
            guard matches(address) else { return .boolean(false) }
            finished = true
            completion(address)
            return .boolean(true)
        }
        retained.append(report)
        let close = session(url, report).object
        return { _ = close?.callAsFunction() }
    }

    private static func credentials(_ method: String, _ options: String,
                                    _ completion: @escaping (String?, String?) -> Void) -> () -> Void {
        guard let call else {
            completion(nil, "NotSupportedError")
            return {}
        }
        let done = JSClosure { (arguments: [JSValue]) -> JSValue in
            completion(arguments.first?.string, arguments.count > 1 ? arguments[1].string : nil)
            return .undefined
        }
        retained.append(done)
        let abort = call(method, options, done).object
        return { _ = abort?.callAsFunction() }
    }
}
#endif
