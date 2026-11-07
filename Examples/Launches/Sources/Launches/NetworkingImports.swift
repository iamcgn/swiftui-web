// The two ways packages reach URLSession off Apple platforms: the whole module beside Foundation
// (`#if canImport(FoundationNetworking)`), and its classes one by one, as swift-openapi-urlsession
// writes. On wasm both have to find WebFoundation's types without an ambiguity; compiled by
// `scripts/build-wasm.sh Examples/Launches` in CI, so one is a build error.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(WASI)
@preconcurrency import struct FoundationNetworking.URLRequest
import class FoundationNetworking.URLSession
import class FoundationNetworking.URLSessionTask
import class FoundationNetworking.URLResponse
import class FoundationNetworking.HTTPURLResponse
#endif

enum NetworkingImports {
    static func request(_ session: URLSession = .shared) -> URLSessionTask {
        var request = URLRequest(url: URL(string: "https://example.com/launches")!)
        request.httpMethod = "HEAD"
        return session.dataTask(with: request) { _, response, _ in
            _ = (response as? HTTPURLResponse)?.statusCode ?? (response as URLResponse?)?.expectedContentLength
        }
    }
}
