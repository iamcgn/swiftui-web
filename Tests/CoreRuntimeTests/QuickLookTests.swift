// Quick Look's preview (Sources/QuickLook): IceCubes' toolbar item and Mlem's thumbnail present
// `quickLookPreview` with a URL; the sheet shows the file and Done clears the binding.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import QuickLook

#if !os(WASI)
@Suite @MainActor struct QuickLookTests {
    @MainActor private final class Box { var url: URL? }

    private func render<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 480))
        runtime.layout(in: CGSize(width: 320, height: 480))
        return runtime
    }

    private func texts(_ runtime: Runtime) -> [String] {
        runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("drawText(") }
    }

    @Test func aURLPresentsItsPreviewAndNilDoesNot() {
        let box = Box()
        let binding = Binding(get: { box.url }, set: { box.url = $0 })
        #expect(!render(Text("Post").quickLookPreview(binding)).hasPresentations)
        box.url = URL(string: "https://example.com/files/report.pdf")
        let runtime = render(Text("Post").quickLookPreview(binding))
        #expect(runtime.hasPresentations)
        let drawn = texts(runtime)
        #expect(drawn.contains { $0.hasPrefix("drawText(\"report.pdf\"") }, "\(drawn)")
        #expect(drawn.contains { $0.hasPrefix("drawText(\"Done\"") }, "\(drawn)")
    }

    @Test func severalItemsPageWithPreviousAndNext() {
        let box = Box()
        let urls = [URL(string: "https://example.com/a.pdf")!, URL(string: "https://example.com/b.pdf")!]
        box.url = urls[1]
        let binding = Binding(get: { box.url }, set: { box.url = $0 })
        let drawn = texts(render(Text("Post").quickLookPreview(binding, in: urls)))
        #expect(drawn.contains { $0.hasPrefix("drawText(\"b.pdf\"") }, "\(drawn)")
        #expect(drawn.contains { $0.hasPrefix("drawText(\"Previous\"") } && drawn.contains { $0.hasPrefix("drawText(\"Next\"") }, "\(drawn)")
    }
}
#endif
