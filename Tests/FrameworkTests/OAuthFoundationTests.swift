// The Foundation names p2's OAuth2 (the OldOS app's sign-in) reaches for: an `HTTPURLResponse`
// extension that overrides its debug description for the log, a request's cache policy named
// on `NSURLRequest`, and errors compared with `isEqual`. Run against Foundation on macOS and
// Linux too, so the wasm forms behave as Apple's.
import Testing
import WebFoundation
import WebFoundationFormats
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(WASI)
import AudioToolbox
#endif

/// A response class an app defines, as an extension's `override open var` needs Foundation's
/// to be open.
private final class LoggedResponse: HTTPURLResponse, @unchecked Sendable {
    override var debugDescription: String { "HTTP/1.1 \(statusCode)" }
}

@Suite struct OAuthFoundationTests {
    @Test func responsesDescribeThemselvesAndAreOpen() throws {
        let url = try #require(URL(string: "https://example.com/token"))
        #if os(WASI) && !canImport(ObjectiveC)
        let plain = URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 4, textEncodingName: nil)
        #expect(plain.description == "<URLResponse> { URL: https://example.com/token }")
        #endif
        let logged = try #require(LoggedResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: [:]))
        let response: URLResponse = logged
        #expect(response.debugDescription == "HTTP/1.1 201")
    }

    @Test func requestsNameTheirCachePolicyOnTheObject() throws {
        let policy: NSURLRequest.CachePolicy = .reloadIgnoringLocalCacheData
        let url = try #require(URL(string: "https://example.com/authorize"))
        let request = URLRequest(url: url, cachePolicy: policy, timeoutInterval: 20)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func errorsAreEqualByDomainCodeAndUserInfo() {
        let first = NSError(domain: "OAuth2", code: 401, userInfo: [NSLocalizedDescriptionKey: "expired"])
        let same = NSError(domain: "OAuth2", code: 401, userInfo: [NSLocalizedDescriptionKey: "expired"])
        #expect(first.isEqual(same) && first.isEqual(first))
        #expect(!first.isEqual(NSError(domain: "OAuth2", code: 403, userInfo: [NSLocalizedDescriptionKey: "expired"])))
        #expect(!first.isEqual(NSError(domain: "Other", code: 401, userInfo: [NSLocalizedDescriptionKey: "expired"])))
        #expect(!first.isEqual(NSError(domain: "OAuth2", code: 401)))
        #if !os(Linux)
        // swift-corelibs-foundation's NSError.isEqual crashes the process (signal 11) when handed
        // a String on Linux; that's Foundation's code, not this package's.
        #expect(!first.isEqual("OAuth2"))
        #endif
        #expect(first.hash == same.hash)
    }

    /// Bodega's `catch CocoaError.fileReadNoSuchFile`: a code matches a Cocoa error with it, as
    /// an error or as an `NSError` in the Cocoa domain, and nothing else.
    @Test func cocoaErrorCodesMatchErrors() {
        func matches(_ error: any Error) -> Bool {
            if case CocoaError.fileReadNoSuchFile = error { return true }
            return false
        }
        #expect(matches(CocoaError(.fileReadNoSuchFile)))
        #expect(!matches(CocoaError(.fileWriteOutOfSpace)))
        #if !os(Linux)
        // On Linux, swift-corelibs-foundation's own `~=` casts an NSError to CocoaError whatever
        // its domain (a "Other" error matched), and the test process later crashed: that cast is
        // Foundation's, not this package's, so the NSError cases run where it holds (Apple
        // platforms, and wasm, where the `~=` is ours).
        #expect(matches(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoSuchFile.rawValue)))
        #expect(!matches(NSError(domain: "Other", code: CocoaError.fileReadNoSuchFile.rawValue)))
        #endif
    }

    #if os(WASI)
    /// IceCubes registers its sounds at launch and plays them by identifier.
    @Test func registeredSoundsGetTheirOwnIdentifiers() throws {
        let url = try #require(URL(string: "file:///sounds/tap.wav"))
        var first: SystemSoundID = 0
        var second: SystemSoundID = 0
        #expect(AudioServicesCreateSystemSoundID(url as CFURL, &first) == 0)
        AudioServicesCreateSystemSoundID(url as CFURL, &second)
        #expect(first > kSystemSoundID_Vibrate && second > first)
        AudioServicesPlaySystemSound(first)
        #expect(AudioServicesDisposeSystemSoundID(first) == 0)
    }
    #endif
}
