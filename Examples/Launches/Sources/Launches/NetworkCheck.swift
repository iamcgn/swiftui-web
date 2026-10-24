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
    static var cross: String? { query("cross") }
    /// The slow fixture server (`?slow=http://127.0.0.1:PORT`, Playwright/fixture-server.mjs).
    static var slow: String? { query("slow") }

    static func query(_ name: String) -> String? {
        #if os(WASI)
        let search = JSObject.global.location.search.string ?? ""
        guard let range = search.range(of: name + "=") else { return nil }
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
            if let slow = PageAddresses.slow {
                // Timeout after the headers: the server sends them at once and the body 3 s later;
                // a 0.3 s timeout fires while the body is being read: -1001, not a response.
                do {
                    var request = URLRequest(url: URL(string: slow + "/slow?ms=3000")!)
                    request.timeoutInterval = 0.3
                    _ = try await session.data(for: request)
                    parts.append("timeout FAILED (answered)")
                } catch let error as URLError { parts.append("timeout \(error.code.rawValue)") }
                catch { parts.append("timeout FAILED \(error)") }
                // In-flight cancel: the headers are in, the body is 1.5 s away, the task is cancelled
                // after 0.2 s: -999, and exactly one completion (the late body never answers twice).
                var completions = 0
                let inFlight = Task { () throws -> Int in
                    do { _ = try await session.data(from: URL(string: slow + "/slow?ms=1500")!); completions += 1; return 0 }
                    catch { completions += 1; throw error }
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                inFlight.cancel()
                do { _ = try await inFlight.value; parts.append("inflight FAILED (answered)") }
                catch let error as URLError { parts.append("inflight \(error.code.rawValue)") }
                catch { parts.append("inflight FAILED \(error)") }
                try? await Task.sleep(nanoseconds: 1_600_000_000)   // past the body's arrival: still one completion
                parts.append("completions \(completions)")
            }
            summary = "network: " + parts.joined(separator: " | ")
        }
    }
}
