// The host's platform profile: the look the root starts in (the canvas host picks iOS on a
// touch device), switchable while mounted, and overridable per subtree.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PlatformProfileTests {
    private static let macFont = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    private static let iOSFont = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body, profile: "iOS")

    private func makeRuntime() -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.macFont, width: nil, string: "Hi"): .init(width: 12, height: 16, firstBaseline: 13, lastBaseline: 13),
            RecordedTextEngine.key(font: Self.iOSFont, width: nil, string: "Hi"): .init(width: 16, height: 24.5, firstBaseline: 18, lastBaseline: 18),
        ])
        return runtime
    }

    private func textCommand(_ runtime: Runtime) -> String? {
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime.render(scale: 2).commands.map(\.description).first { $0.hasPrefix("drawText") }
    }

    @Test func hostProfileSelectsTheLook() {
        let runtime = makeRuntime()
        #expect(runtime.hostPlatformProfile.name == "macOS")
        runtime.mount(Text("Hi"))
        #expect(textCommand(runtime)?.contains("system 13 w400") == true)
        // Switching while mounted re-applies the tree: the default font becomes iOS's body.
        runtime.hostPlatformProfile = .iOS
        #expect(runtime.hostPlatformProfile.name == "iOS")
        #expect(textCommand(runtime)?.contains("system 17 w400") == true)
        runtime.hostPlatformProfile = .macOS
        #expect(textCommand(runtime)?.contains("system 13 w400") == true)
    }

    @Test func subtreesKeepTheirOwnProfile() {
        let runtime = makeRuntime()
        runtime.hostPlatformProfile = .iOS
        runtime.mount(Text("Hi").environment(\.platformProfile, .macOS))
        #expect(textCommand(runtime)?.contains("system 13 w400") == true)
    }
}
#endif
