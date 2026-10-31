// The everyday API batch (Docs/coverage.md's ranking): `@AppStorage` and `defaultAppStorage`,
// `allowsHitTesting`, `Color.gradient`, Liquid Glass, `sensoryFeedback`, `ImageRenderer` and
// the `UTType` lookups.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebFoundation

#if !os(WASI)
@MainActor private final class Taps { var below = 0; var above = 0 }

private enum Store {
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: "swiftui-web.everyday-tests")!
}

private struct StoredCounter: View {
    @AppStorage("everyday.count", store: Store.defaults) var count = 0
    var body: some View { Button("n\(count)") { count += 1 }.buttonStyle(.plain) }
}

private struct StoredMirror: View {
    @AppStorage("everyday.count", store: Store.defaults) var count = 0
    var body: some View { Text("m\(count)") }
}

private struct EnvironmentStored: View {
    @AppStorage("everyday.mode") var mode = "none"
    @AppStorage("everyday.missing") var missing: String?
    var body: some View { Text("\(mode) \(missing ?? "nil")") }
}

private enum Flavor: String { case vanilla, mint }

private struct RawStored: View {
    @AppStorage("everyday.flavor", store: Store.defaults) var flavor = Flavor.vanilla
    var body: some View { Text(flavor.rawValue) }
}

@Suite(.serialized) @MainActor struct EverydayAPITests {
    private func texts(_ runtime: Runtime) -> [String] {
        runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }
    }

    private func tap(_ renderer: HeadlessRenderer, _ point: CGPoint) {
        renderer.runtime.pointerDown(at: point)
        renderer.runtime.pointerUp(at: point)
        renderer.renderFrame()
    }

    @Test func appStorageReadsWritesAndUpdatesEveryView() throws {
        for key in ["everyday.count", "everyday.mode", "everyday.missing", "everyday.flavor"] { Store.defaults.removeObject(forKey: key) }
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: MonospaceTextEngine())
        renderer.mount(VStack { StoredCounter()._probe("counter"); StoredMirror() })
        renderer.renderFrame()
        #expect(texts(renderer.runtime) == ["n0", "m0"])
        let frame = try #require(renderer.probeFrames["counter"])
        tap(renderer, CGPoint(x: frame.midX, y: frame.midY))
        #expect(Store.defaults.integer(forKey: "everyday.count") == 1)
        #expect(texts(renderer.runtime) == ["n1", "m1"])

        // A store set above the views serves the properties without one of their own.
        Store.defaults.set("dark", forKey: "everyday.mode")
        renderer.mount(EnvironmentStored().defaultAppStorage(Store.defaults))
        renderer.renderFrame()
        #expect(texts(renderer.runtime) == ["dark nil"])

        // Raw-value enums go in as their raw values.
        Store.defaults.set("mint", forKey: "everyday.flavor")
        renderer.mount(RawStored())
        renderer.renderFrame()
        #expect(texts(renderer.runtime) == ["mint"])
    }

    @Test func hitTestingOffLetsPressesThrough() {
        let taps = Taps()
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100))
        renderer.mount(ZStack {
            Color.blue.frame(width: 100, height: 100).onTapGesture { taps.below += 1 }
            Color.red.frame(width: 100, height: 100).onTapGesture { taps.above += 1 }.allowsHitTesting(false)
        })
        renderer.renderFrame()
        tap(renderer, CGPoint(x: 100, y: 50))
        #expect(taps.below == 1 && taps.above == 0)

        // Below the gesture, the content has nothing to hit either.
        renderer.mount(ZStack {
            Color.blue.frame(width: 100, height: 100).onTapGesture { taps.below += 1 }
            Color.red.frame(width: 100, height: 100).allowsHitTesting(false).onTapGesture { taps.above += 1 }
        })
        renderer.renderFrame()
        tap(renderer, CGPoint(x: 100, y: 50))
        #expect(taps.below == 2 && taps.above == 0)

        // On, it changes nothing.
        renderer.mount(ZStack {
            Color.blue.frame(width: 100, height: 100).onTapGesture { taps.below += 1 }
            Color.red.frame(width: 100, height: 100).onTapGesture { taps.above += 1 }.allowsHitTesting(true)
        })
        renderer.renderFrame()
        tap(renderer, CGPoint(x: 100, y: 50))
        #expect(taps.below == 2 && taps.above == 1)
    }

    @Test func colorGradientRunsTopToBottom() {
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100))
        renderer.mount(Rectangle().fill(Color.red.gradient).frame(width: 40, height: 60))
        var gradients: [DisplayGradient] = []
        for command in renderer.renderFrame().commands {
            if case .fillGradient(_, let g, _) = command { gradients.append(g) }
        }
        #expect(gradients.count == 1)
        guard let gradient = gradients.first else { return }
        if case .linear(let start, let end) = gradient.kind {
            #expect(start == CGPoint(x: 100, y: 20) && end == CGPoint(x: 100, y: 80))
        } else { Issue.record("expected a linear gradient") }
        // Lighter at the top, the colour itself at the bottom.
        #expect(gradient.stops.count == 2 && gradient.stops[0].color.green > gradient.stops[1].color.green)
        #expect(AnyGradient(Gradient(colors: [.red, .blue])) != Color.red.gradient)
    }

    @Test func glassDrawsAMaterialAndStylesCompile() {
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: MonospaceTextEngine())
        renderer.mount(VStack {
            Text("Glass").padding().glassEffect(.regular.tint(.blue).interactive(), in: RoundedRectangle(cornerRadius: 8))
            Text("None").glassEffect(.identity)
            GlassEffectContainer(spacing: 8) {
                Button("A") {}.buttonStyle(.glass)
                Button("B") {}.buttonStyle(.glassProminent)
                Button("C") {}.buttonStyle(.glass(.clear))
            }
        }
        .sensoryFeedback(.success, trigger: 1)
        .sensoryFeedback(trigger: 2) { _, _ in .impact(weight: .heavy) })
        let painted = renderer.renderFrame().commands.map(\.description)
        #expect(painted.contains { $0.hasPrefix("drawText(\"Glass\"") } && painted.contains { $0.hasPrefix("drawText(\"C\"") })
        #expect(painted.count > 6, "\(painted)")
    }

    @Test func imageRendererDrawsItsContent() {
        let renderer = ImageRenderer(content: Color.red.frame(width: 30, height: 20))
        let drawn = renderer._draw()
        #expect(drawn.size == CGSize(width: 30, height: 20))
        #expect(drawn.commands.map(\.description).contains { $0.hasPrefix("fillRect(0, 0, 30, 20)") }, "\(drawn.commands.map(\.description))")
        renderer.proposedSize = ProposedViewSize(width: 50, height: 50)
        #expect(renderer._draw().size == CGSize(width: 30, height: 20))
        #expect(ImageRenderer(content: EmptyView())._draw().commands.isEmpty)
    }

    @Test func uniformTypesConformAndName() {
        #expect(UTType.png.conforms(to: .image) && UTType.swiftSource.conforms(to: .text) && UTType.mpeg4Movie.conforms(to: .audiovisualContent))
        #expect(!UTType.png.conforms(to: .text) && UTType.png.isSubtype(of: .image) && UTType.image.isSupertype(of: .jpeg))
        #expect(UTType(mimeType: "image/png") == .png && UTType(mimeType: "video/mp4") == .mpeg4Movie && UTType(mimeType: "x-unknown/thing") == nil)
        #expect(UTType.png.preferredMIMEType == "image/png" && UTType.gif.preferredMIMEType == "image/gif" && UTType.data.preferredMIMEType == nil)
        #expect(UTType(filenameExtension: "json", conformingTo: .text) == .json && UTType(filenameExtension: "png", conformingTo: .text) == nil)
        #expect(UTType(exportedAs: "com.example.notes").identifier == "com.example.notes" && UTType.png.description == "public.png")
        #expect(UTType.png.supertypes.contains(.image) && UTType.png.supertypes.contains(.data))
    }
}
#endif
