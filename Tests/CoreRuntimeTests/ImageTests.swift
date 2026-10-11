// Image (Phase 2): catalog variant selection, sizing, template tinting, the drawImage command
// and its encoding, named colours. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ImageTests {
    static let catalog = AssetCatalog(
        images: [
            "sliced": ImageResource(name: "sliced", variants: [ImageVariant(file: "sliced@2x.png", scale: 2, pixelWidth: 80, pixelHeight: 80)],
                                    capInsets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), tilesCenter: true),
            "vector": ImageResource(name: "vector", variants: [ImageVariant(file: "vector.svg", scale: 1, pixelWidth: 40, pixelHeight: 30, isVector: true)]),
            "swatch": ImageResource(name: "swatch", variants: [
                ImageVariant(file: "swatch.png", scale: 1, pixelWidth: 64, pixelHeight: 40),
                ImageVariant(file: "swatch@2x.png", scale: 2, pixelWidth: 128, pixelHeight: 80),
            ]),
            "icon": ImageResource(name: "icon", isTemplate: true, variants: [
                ImageVariant(file: "icon@2x.png", scale: 2, pixelWidth: 48, pixelHeight: 48),
            ]),
            "badge": ImageResource(name: "badge", variants: [
                ImageVariant(file: "badge@2x.png", scale: 2, pixelWidth: 40, pixelHeight: 40, idiom: "universal"),
                ImageVariant(file: "badge~mac@2x.png", scale: 2, pixelWidth: 40, pixelHeight: 40, idiom: "mac"),
                ImageVariant(file: "badge~ipad@2x.png", scale: 2, pixelWidth: 40, pixelHeight: 40, idiom: "ipad"),
            ]),
            "dual": ImageResource(name: "dual", variants: [
                ImageVariant(file: "dual@2x.png", scale: 2, pixelWidth: 96, pixelHeight: 48),
                ImageVariant(file: "dual-dark@2x.png", scale: 2, pixelWidth: 96, pixelHeight: 48, appearance: "dark"),
            ]),
        ],
        colors: [
            "Accent": [ColorVariant(red: 0, green: 0.533, blue: 1)],
            "Panel": [ColorVariant(red: 0.95, green: 0.95, blue: 0.97), ColorVariant(appearance: "dark", red: 0.1, green: 0.1, blue: 0.12)],
        ])

    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100), scale: CGFloat = 2,
                                 environment: EnvironmentValues = EnvironmentValues()) -> (frames: [String: CGRect], commands: [String]) {
        let renderer = HeadlessRenderer(size: size, scale: scale, assets: Self.catalog)
        renderer.mount(view.environment(\.colorScheme, environment.colorScheme))
        let list = renderer.renderFrame()
        return (renderer.probeFrames, list.commands.map(\.description))
    }

    @Test func variantSelection() {
        let badge = Self.catalog.image(named: "badge")!
        #expect(badge.variant(scale: 2, scheme: .light, idiom: "mac")?.file == "badge~mac@2x.png")
        #expect(badge.variant(scale: 2, scheme: .light, idiom: "iphone")?.file == "badge@2x.png")
        let swatch = Self.catalog.image(named: "swatch")!
        #expect(swatch.variant(scale: 1, scheme: .light, idiom: "mac")?.file == "swatch.png")
        #expect(swatch.variant(scale: 3, scheme: .light, idiom: "mac")?.file == "swatch@2x.png")   // the largest when none matches
        #expect(swatch.pointSize(scheme: .light, idiom: "mac") == CGSize(width: 64, height: 40))
        let dual = Self.catalog.image(named: "dual")!
        #expect(dual.variant(scale: 2, scheme: .light, idiom: "mac")?.file == "dual@2x.png")
        #expect(dual.variant(scale: 2, scheme: .dark, idiom: "mac")?.file == "dual-dark@2x.png")
        #expect(Self.catalog.color(named: "Panel", scheme: .dark) == RGBA(red: 0.1, green: 0.1, blue: 0.12))
        #expect(Self.catalog.color(named: "Panel", scheme: .light) == RGBA(red: 0.95, green: 0.95, blue: 0.97))
        #expect(Self.catalog.color(named: "Nope", scheme: .light) == nil)
    }

    @Test func rigidAndResizableSizes() {
        let rigid = render(Image("swatch")._probe("image"))
        #expect(rigid.frames["image"] == CGRect(x: 68, y: 30, width: 64, height: 40))
        #expect(rigid.commands == ["drawImage(swatch@2x.png @2x (68, 30, 64, 40))"])
        let one = render(Image("swatch")._probe("image"), scale: 1)
        #expect(one.commands == ["drawImage(swatch.png @1x (68, 30, 64, 40))"])
        let resizable = render(Image("swatch").resizable().frame(width: 30, height: 30)._probe("frame"))
        #expect(resizable.commands == ["drawImage(swatch@2x.png @2x (85, 35, 30, 30))"])
        let missing = render(Image("nothing")._probe("image"))
        #expect(missing.frames["image"] == CGRect(x: 100, y: 50, width: 0, height: 0))
        #expect(missing.commands.isEmpty)
        let symbol = render(Image(systemName: "star")._probe("image"))
        #expect(symbol.frames["image"]?.size == CGSize(width: 16.5, height: 16))
    }

    @Test func templateTint() {
        #expect(render(Image("icon")).commands == ["drawImage(icon@2x.png @2x (88, 38, 24, 24) tint=#000000@0.85)"])
        #expect(render(Image("icon").foregroundColor(.red)).commands == ["drawImage(icon@2x.png @2x (88, 38, 24, 24) tint=#FF383C)"])
        #expect(render(Image("icon").renderingMode(.original)).commands == ["drawImage(icon@2x.png @2x (88, 38, 24, 24))"])
        #expect(render(Image("swatch").renderingMode(.template).foregroundStyle(.blue)).commands
                == ["drawImage(swatch@2x.png @2x (68, 30, 64, 40) tint=#0088FF)"])
        #expect(render(Image("icon").renderingMode(.template).renderingMode(nil).renderingMode(.original)).commands
                == ["drawImage(icon@2x.png @2x (88, 38, 24, 24))"])
    }

    @Test func resizingModes() {
        let sliced = render(Image("swatch").resizable(capInsets: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)).frame(width: 100, height: 60))
        #expect(sliced.commands == ["drawImage(swatch@2x.png @2x (50, 20, 100, 60) insets=4,6,4,6)"])
        let tiled = render(Image("swatch").resizable(resizingMode: .tile).interpolation(.none).frame(width: 100, height: 60))
        #expect(tiled.commands == ["drawImage(swatch@2x.png @2x (50, 20, 100, 60) tile nearest)"])
    }

    @Test func encodingRoundTrip() {
        var list = DisplayList()
        var draw = ImageDraw(file: "a.png", scale: 2, pixelSize: CGSize(width: 10, height: 20), rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        draw.capInsets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        draw.tiles = true
        draw.smoothing = false
        draw.tint = RGBA(red: 1, green: 0, blue: 0, alpha: 0.5)
        list.append(.drawImage(draw))
        list.append(.drawImage(ImageDraw(file: "b.png", scale: 1, pixelSize: CGSize(width: 5, height: 5), rect: CGRect(x: 0, y: 0, width: 5, height: 5))))
        let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
        #expect(encoded.strings == ["a.png", "b.png"])
        #expect(DisplayListDecoder.decode(encoded) == [
            "drawImage a.png @2.0x 10x20 1.0,2.0,3.0,4.0 tile insets 1.0,2.0,3.0,4.0 nearest tint rgba(255,0,0,0.5)",
            "drawImage b.png @1.0x 5x5 0.0,0.0,5.0,5.0 insets 0.0,0.0,0.0,0.0",
        ])
    }

    @Test func aspectRatioProposals() {
        // A colour follows the ratio; a rigid image ignores it; one dimension derives the other.
        let color = render(Color.blue.aspectRatio(2, contentMode: .fit)._probe("ratio").frame(width: 100, height: 100))
        #expect(color.frames["ratio"] == CGRect(x: 50, y: 25, width: 100, height: 50))
        let fill = render(Color.blue.aspectRatio(2, contentMode: .fill)._probe("ratio").frame(width: 100, height: 100))
        #expect(fill.frames["ratio"] == CGRect(x: 0, y: 0, width: 200, height: 100))
        let rigid = render(Image("swatch").scaledToFit()._probe("image").frame(width: 100, height: 100))
        #expect(rigid.frames["image"]?.size == CGSize(width: 64, height: 40))
        let widthOnly = render(Image("swatch").resizable().scaledToFit()._probe("image").frame(width: 100))
        #expect(widthOnly.frames["image"]?.size == CGSize(width: 100, height: 62.5))
        let none = render(Image("swatch").resizable().scaledToFill()._probe("image").fixedSize())
        #expect(none.frames["image"]?.size == CGSize(width: 64, height: 40))
    }

    @Test func namedColors() {
        #expect(render(Color("Accent").frame(width: 10, height: 10)).commands == ["fillRect(95, 45, 10, 10) #0088FF"])
        #expect(render(Color("Nope").frame(width: 10, height: 10)).commands.isEmpty)
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        #expect(render(Color("Panel").frame(width: 10, height: 10), environment: dark).commands == ["fillRect(95, 45, 10, 10) #1A1A1F"])
        #expect(render(Image("dual")._probe("i"), environment: dark).commands == ["drawImage(dual-dark@2x.png @2x (76, 38, 48, 24))"])
    }

    /// sw-images: a catalog's slicing applies to a resizable image unless the view slices itself,
    /// a vector set lays out at its point size and draws its file at scale 1 (the painters scale
    /// it sharply), and `Image(size:label:renderer:)` draws its closure scaled into the frame.
    @Test func slicingVectorsAndRenderedImages() {
        let sliced = render(Image("sliced").resizable().frame(width: 120, height: 80)._probe("image"))
        #expect(sliced.commands == ["drawImage(sliced@2x.png @2x (40, 10, 120, 80) insets=8,8,8,8 tile)"], "\(sliced.commands)")
        let own = render(Image("sliced").resizable(capInsets: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)).frame(width: 120, height: 80))
        #expect(own.commands == ["drawImage(sliced@2x.png @2x (40, 10, 120, 80) insets=4,4,4,4)"], "\(own.commands)")
        #expect(render(Image("sliced").frame(width: 120, height: 80)).commands == ["drawImage(sliced@2x.png @2x (80, 30, 40, 40))"])
        let vector = render(Image("vector")._probe("image"))
        #expect(vector.frames["image"]?.size == CGSize(width: 40, height: 30) && vector.commands == ["drawImage(vector.svg @1x (80, 35, 40, 30))"], "\(vector.commands)")
        #expect(render(Image("vector").resizable().frame(width: 80, height: 60)).commands == ["drawImage(vector.svg @1x (60, 20, 80, 60))"])
        let drawn = render(Image(size: CGSize(width: 40, height: 30)) { context in
            context.fill(Path(CGRect(x: 0, y: 0, width: 40, height: 30)), with: .color(.red))
        }._probe("image"))
        #expect(drawn.frames["image"]?.size == CGSize(width: 40, height: 30))
        #expect(drawn.commands == ["save", "clipRect(80, 35, 40, 30)", "save", "concat(1, 0, 0, 1, 80, 35)", "fillPath(5 elements) #FF383C", "restore", "restore"], "\(drawn.commands)")
        let big = render(Image(size: CGSize(width: 40, height: 30)) { context in
            context.fill(Path(CGRect(x: 0, y: 0, width: 40, height: 30)), with: .color(.red))
        }.resizable().renderingMode(.template).foregroundStyle(.green).frame(width: 80, height: 60))
        #expect(big.commands.contains("concat(2, 0, 0, 2, 60, 20)") && big.commands.contains("fillPath(5 elements) #34C759"), "\(big.commands)")
    }

    @Test func replacingTheCatalogReEvaluates() {
        let runtime = Runtime()
        runtime.mount(Image("swatch")._probe("image"))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["image"]?.size == .zero)
        runtime.assetCatalog = Self.catalog
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["image"]?.size == CGSize(width: 64, height: 40))
    }
}
#endif
