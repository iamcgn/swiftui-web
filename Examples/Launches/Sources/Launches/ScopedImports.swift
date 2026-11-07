// A file that imports single Foundation declarations by kind, as swift-openapi-runtime and other
// packages do (`import struct Foundation.URL`). On wasm each of these names is WebFoundation's,
// declared over FoundationEssentials' (decision 0017), and the import has to find one of them.
// Compiled by `scripts/build-wasm.sh Examples/Launches` in CI; an ambiguity here is a build error.
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.Data
import protocol Foundation.LocalizedError
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder

enum ScopedImports {
    struct Failure: LocalizedError { var errorDescription: String? { "scoped" } }

    static func check() -> String {
        let url = URL(string: "https://example.com/a?b=c")
        let host = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.host } ?? ""
        let data = (try? JSONEncoder().encode([1, 2])) ?? Data()
        let numbers = (try? JSONDecoder().decode([Int].self, from: data)) ?? []
        return "\(host) \(numbers.count) \(Failure().localizedDescription)"
    }
}
