// The Foundation calls swift-openapi-runtime makes that WebFoundation lacked: a replacement
// limited to a range, and a CharacterSet written as an array literal. The cases run against
// Foundation on macOS and Linux too.
import Testing
import WebFoundation

@Suite struct OpenAPIRuntimeGapsTests {
    @Test func replacementStaysInsideItsRange() throws {
        var path = "/users/{}/posts/{}"
        for value in ["42", "7"] {
            let range = try #require(path.range(of: "{}"))
            path = path.replacingOccurrences(of: "{}", with: value, range: range)
        }
        #expect(path == "/users/42/posts/7")
    }

    @Test func aNilRangeReplacesEverywhere() {
        #expect("a-b-c".replacingOccurrences(of: "-", with: "+", options: [], range: nil) == "a+b+c")
    }

    @Test func arrayLiteralCharacterSet() {
        let quotes: CharacterSet = ["\"", "'"]
        #expect(quotes.contains("\""))
        #expect(quotes.contains("'"))
        #expect(!quotes.contains("a"))
        #expect("\"inline\"".trimmingCharacters(in: ["\""]) == "inline")
    }

    @Test func scalarRangeCharacterSet() {
        let lower = CharacterSet(charactersIn: "a"..."z")
        #expect(lower.contains("q"))
        #expect(!lower.contains("Q"))
    }
}
