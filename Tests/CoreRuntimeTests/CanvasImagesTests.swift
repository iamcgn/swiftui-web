// Phase 8 step 6, sw-canvas: images and symbols drawn through nodes, blend modes and filters
// wrapping each operation, tiled shadings, and a state read by the renderer repainting the
// canvas (Docs/elements/Canvas.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Observable private final class Model { var shade = 0.2 }

private struct Reading: View {
    let model: Model
    var body: some View {
        Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 20, height: 20)), with: .color(Color(white: model.shade)))
        }
        .frame(width: 40, height: 40)
    }
}

@Suite @MainActor struct CanvasImagesTests {
    private func commands<V: View>(_ view: V) -> [String] {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime.render(scale: 2).commands.map(\.description)
    }

    @Test func symbolsBlendModesAndFiltersWrapEachOperation() {
        let painted = commands(Canvas { context, _ in
            if let box = context.resolveSymbol(id: "box") { context.draw(box, in: CGRect(x: 10, y: 10, width: 30, height: 20)) }
            #expect(context.resolveSymbol(id: "missing") == nil)
            var blended = context
            blended.blendMode = .multiply
            blended.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(.red))
            var filtered = context
            filtered.addFilter(.blur(radius: 2))
            filtered.addFilter(.shadow(color: .black, radius: 3, x: 1, y: 1))
            filtered.stroke(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(.blue), lineWidth: 2)
            var grey = context
            grey.addFilter(.grayscale(1))
            grey.fill(Path(CGRect(x: 50, y: 50, width: 10, height: 10)), with: .color(.green))
        } symbols: {
            Color.purple.tag("box")
        }.frame(width: 200, height: 100))
        // The symbol: the purple colour painted into its rect.
        #expect(painted.contains { $0.hasPrefix("fillRect(10, 10, 30, 20)") })
        // Each operation in its own groups: the blend, then the blur and shadow around the stroke.
        #expect(painted.contains { $0.hasPrefix("beginBlend(multiply") })
        let blurIndex = painted.firstIndex { $0.hasPrefix("beginFilter(blur(2") }
        let shadowIndex = painted.firstIndex { $0.hasPrefix("beginShadow") }
        let strokeIndex = painted.firstIndex { $0.hasPrefix("strokePath") }
        #expect(blurIndex != nil && shadowIndex != nil && strokeIndex != nil && blurIndex! < shadowIndex! && shadowIndex! < strokeIndex!)
        #expect(painted.filter { $0 == "endGroup" }.count == 4)
        #expect(painted.contains { $0.hasPrefix("beginFilter(") && $0.contains("0.2126") })
    }

    @Test func imagesAndTiledShadingsDrawThroughTheCatalog() {
        // Without a catalog entry the image draws nothing; a symbol draws its stand-in glyph.
        let painted = commands(Canvas { context, _ in
            context.draw(Image("nowhere"), in: CGRect(x: 0, y: 0, width: 20, height: 20))
            context.draw(Image(systemName: "star.fill"), at: CGPoint(x: 50, y: 50))
            context.fill(Path(CGRect(x: 0, y: 0, width: 40, height: 40)), with: .tiledImage(Image("nowhere")))
            let resolved = context.resolve(Image(systemName: "star.fill"))
            #expect(resolved.size.width > 0)
        }.frame(width: 200, height: 100))
        #expect(!painted.contains { $0.hasPrefix("drawImage") })
        #expect(painted.contains { $0.hasPrefix("fillPath") || $0.hasPrefix("strokePath") })
    }

    @Test func aStateReadByTheRendererRepaints() {
        let model = Model()
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(Reading(model: model))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let before = runtime.render(scale: 2).commands.map(\.description)
        model.shade = 0.8
        runtime.layout(in: CGSize(width: 200, height: 100))
        let after = runtime.render(scale: 2).commands.map(\.description)
        #expect(before != after && after.contains { $0.hasPrefix("fillPath") && $0.hasSuffix("#CCCCCC") })
    }
}
#endif
