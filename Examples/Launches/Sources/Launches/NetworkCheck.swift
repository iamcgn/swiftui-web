// URLSession over the host's fetch (decision 0021, pf-urlsession), against local fixtures the
// probe serves: a same-origin JSON file (200 with its bytes and content type), a missing path
// (404 as a response, never an error), and a cross-origin request to a second local server
// that sends no CORS headers (the browser refuses it: a transport failure, never a status) —
// plus a cancellation. The results are shown as one line the probe reads. Nothing here goes
// to the network beyond 127.0.0.1.
import Foundation
import SwiftUI
#if os(WASI)
import JavaScriptKit
#endif

/// The page's origin and the second server's (`?cross=http://127.0.0.1:PORT`), from the page.
enum PageAddresses {
    static var origin: String {
        #if os(WASI)
        return JSObject.global.location.origin.string ?? ""
        #else
        return ""
        #endif
    }
    static var cross: String? {
        #if os(WASI)
        let search = JSObject.global.location.search.string ?? ""
        guard let range = search.range(of: "cross=") else { return nil }
        let value = search[range.upperBound...].prefix { $0 != "&" }
        return value.removingPercentEncoding
        #else
        return nil
        #endif
    }
}

@MainActor
final class NetworkCheck: ObservableObject {
    @Published var summary = "network: pending"

    func run() {
        Task { @MainActor in
            let origin = PageAddresses.origin
            var parts: [String] = []
            let session = URLSession(configuration: .default)
            // 200: the fixture, as JSON, through a request with a header.
            do {
                var request = URLRequest(url: URL(string: origin + "/fixtures/country.json")!)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                struct Country: Decodable { let name: String; let alpha3Code: String }
                let country = try JSONDecoder().decode(Country.self, from: data)
                parts.append("ok \(http?.statusCode ?? -1) \(country.name)/\(country.alpha3Code) \(http?.mimeType ?? "?")")
            } catch { parts.append("ok FAILED \(error)") }
            // 404: a response with its status, not an error.
            do {
                let (data, response) = try await session.data(from: URL(string: origin + "/fixtures/missing.json")!)
                parts.append("missing \((response as? HTTPURLResponse)?.statusCode ?? -1) \(data.count > 0 ? "body" : "empty")")
            } catch { parts.append("missing FAILED \(error)") }
            // CORS: the other local server sends no Access-Control-Allow-Origin: a URLError, no status.
            if let other = PageAddresses.cross {
                do {
                    _ = try await session.data(from: URL(string: other + "/fixtures/country.json")!)
                    parts.append("cors FAILED (a refused request came back as a response)")
                } catch let error as URLError { parts.append("cors \(error.code.rawValue)") }
                catch { parts.append("cors FAILED \(error)") }
            }
            // Cancel: the Swift task cancelled before the answer: URLError.cancelled.
            let fetching = Task { try await session.data(from: URL(string: origin + "/fixtures/country.json")!) }
            fetching.cancel()
            do { _ = try await fetching.value; parts.append("cancel FAILED (answered)") }
            catch let error as URLError { parts.append("cancel \(error.code.rawValue)") }
            catch { parts.append("cancel FAILED \(error)") }
            summary = "network: " + parts.joined(separator: " | ")
        }
    }
}
