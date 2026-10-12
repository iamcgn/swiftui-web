// `#Preview` (Phase 3; sw-previews 2026-10-11): preview blocks keep their bodies as
// registrations the registry finds in the binary's conformance records and renders; traits
// carry a fixed layout and `PreviewModifier`s; a PreviewProvider conformance compiles too.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#Preview {
    Text("Hello preview")
}

#Preview("Named", traits: .sizeThatFitsLayout) {
    VStack { Text("One"); Text("Two") }
}

struct SamplePreviews: PreviewProvider {
    static var previews: some View { Text("Sample") }
}

/// A modifier whose context arrives asynchronously.
struct Greeting: PreviewModifier {
    static func makeSharedContext() async throws -> String { "Hi" }
    func body(content: PreviewModifierContent, context: String) -> some View { VStack { Text(context); content } }
}

#Preview("Modified", traits: .modifier(Greeting()), .fixedLayout(width: 120, height: 80)) {
    Text("Body")
}

@Suite @MainActor struct PreviewTests {
    @Test func previewsRegisterAndRender() async {
        #if canImport(MachO)
        let previews = _PreviewRegistry.all.filter { $0.file.hasSuffix("PreviewTests.swift") }
        #expect(previews.map(\.name) == [nil, "Named", "Modified"], "\(previews.map(\.displayName))")
        #else
        // Linux reads no conformance records: the previews stand in by hand (the generated index's shape).
        let previews = [
            _Preview(name: nil, traits: [], file: "CoreRuntimeTests/PreviewTests.swift", line: 8) { Text("Hello preview") },
            _Preview(name: "Named", traits: [.sizeThatFitsLayout], file: "CoreRuntimeTests/PreviewTests.swift", line: 12) { VStack { Text("One"); Text("Two") } },
            _Preview(name: "Modified", traits: [.modifier(Greeting()), .fixedLayout(width: 120, height: 80)], file: "CoreRuntimeTests/PreviewTests.swift", line: 26) { Text("Body") },
        ]
        #expect(_PreviewRegistry.all.isEmpty)
        #endif
        guard previews.count == 3 else { return }
        #expect(previews[1].displayName == "Named" && previews[0].displayName == "PreviewTests.swift:8", "\(previews[0].file) \(previews[0].line)")
        #expect(previews[2].fixedSize == CGSize(width: 120, height: 80) && previews[0].fixedSize == nil)
        // The kept body renders.
        let r = Runtime()
        r.textEngine = MonospaceTextEngine()
        r.mount(previews[0].makeView())
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(r.render(scale: 1).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Hello preview\"") })
        // A modifier wraps the body once its context is made.
        let m = Runtime()
        m.textEngine = MonospaceTextEngine()
        m.mount(previews[2].makeView())
        m.layout(in: CGSize(width: 200, height: 100))
        for _ in 0..<20 where !m.render(scale: 1).commands.map(\.description).contains(where: { $0.hasPrefix("drawText(\"Body\"") }) {
            try? await Task.sleep(nanoseconds: 10_000_000)
            m.layout(in: CGSize(width: 200, height: 100))
        }
        let texts = m.render(scale: 1).commands.map(\.description).filter { $0.hasPrefix("drawText") }
        #expect(texts.contains { $0.hasPrefix("drawText(\"Hi\"") } && texts.contains { $0.hasPrefix("drawText(\"Body\"") }, "\(texts)")
        // Registered previews (the generated index) join the list once: the three discovered
        // ones stay three on Apple platforms; on Linux the registered one is the only one.
        _PreviewRegistry.registered = [previews[1]]
        #if canImport(MachO)
        #expect(_PreviewRegistry.all.filter { $0.file.hasSuffix("PreviewTests.swift") }.count == 3)
        #else
        #expect(_PreviewRegistry.all.filter { $0.file.hasSuffix("PreviewTests.swift") }.count == 1)
        #endif
        _PreviewRegistry.registered = []
    }
}
