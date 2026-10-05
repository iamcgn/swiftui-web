// The public wasm URL delegates to the RFC 3986 core, including opaque/rootless paths.
#if os(WASI)
import Testing
import WebFoundation

@Suite struct WasmURLTests {
    @Test func keepsRootlessPathComponents() throws {
        let mail = try #require(URL(string: "mailto:someone%40example.com?subject=Hello#top"))
        #expect(mail.path == "someone@example.com")
        #expect(mail.lastPathComponent == "someone@example.com")
        #expect(mail.pathExtension == "com")
        #expect(mail.pathComponents == ["someone@example.com"])
        #expect(mail.query == "subject=Hello" && mail.fragment == "top")
        let about = try #require(URL(string: "about:blank"))
        #expect(about.lastPathComponent == "blank" && about.pathComponents == ["blank"])
        let escaped = try #require(URL(string: "custom:dir/a%2Fb.txt"))
        #expect(escaped.lastPathComponent == "a/b.txt")
        #expect(escaped.pathComponents == ["dir", "a/b.txt"])
        #expect(escaped.pathExtension == "txt")
    }
}
#endif
