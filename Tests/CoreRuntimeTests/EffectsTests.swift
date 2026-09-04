// Phase 6: shadow (a shadow group in the display list), zIndex (paint order and hit testing),
// hidden (layout kept, nothing painted, hit tested or exposed), colour effects, blur and blend
// modes (filter and blend groups; the matrices against Apple's measured pixels).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Counter { var taps = 0 }

@Suite @MainActor struct EffectsTests {
    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100)) -> [String] {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime.render(scale: 2).commands.map(\.description)
    }

    @Test func shadowWrapsTheContentInAShadowGroup() {
        let commands = render(Color.red.frame(width: 20, height: 10).shadow(color: .black, radius: 4, x: 2, y: 3))
        #expect(commands == ["beginShadow(#000000 r=4 dx=2 dy=3)", "fillRect(90, 45, 20, 10) #FF383C", "endGroup"])
        // The default colour is a third-opaque black; a clear colour paints no group.
        #expect(render(Color.red.frame(width: 20, height: 10).shadow(radius: 1)).first == "beginShadow(#000000@0.33 r=1 dx=0 dy=0)")
        #expect(render(Color.red.frame(width: 20, height: 10).shadow(color: .clear, radius: 1)) == ["fillRect(90, 45, 20, 10) #FF383C"])
        // Per element on a list.
        let list = render(VStack(spacing: 0) {
            Group { Color.red.frame(width: 20, height: 10); Color.red.frame(width: 20, height: 10) }.shadow(color: .black, radius: 2)
        })
        #expect(list.filter { $0.hasPrefix("beginShadow") }.count == 2)
    }

    @Test func shadowEncodesAndDecodes() {
        var list = DisplayList()
        list.append(.beginShadow(RGBA(r: 0, g: 0, b: 0, a: 0.5), radius: 3, offset: CGSize(width: 1, height: -2)))
        list.append(.endGroup)
        let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
        #expect(DisplayListDecoder.decode(encoded) == ["beginShadow rgba(0,0,0,0.5) r3.0 1.0,-2.0", "endGroup"])
    }

    @Test func linearColorSpaceConvertsToSRGB() {
        let environment = EnvironmentValues()
        #expect(Color(.sRGBLinear, white: 0, opacity: 0.33).resolve(in: environment) == RGBA(red: 0, green: 0, blue: 0, alpha: 0.33))
        let mid = Color(.sRGBLinear, white: 0.5).resolve(in: environment)
        #expect(abs(mid.red - 0.7354) < 0.001)
        #expect(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6).resolve(in: environment) == RGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    }

    @Test func zIndexOrdersSiblingsAndHitTesting() {
        let commands = render(ZStack {
            Color.red.frame(width: 40, height: 40).zIndex(1)
            Color.blue.frame(width: 40, height: 40)
            Color.green.frame(width: 40, height: 40).zIndex(-1)
        })
        #expect(commands == ["fillRect(80, 30, 40, 40) #34C759", "fillRect(80, 30, 40, 40) #0088FF", "fillRect(80, 30, 40, 40) #FF383C"])
        // Equal values keep declaration order; the value survives other modifiers.
        let ties = render(ZStack {
            Color.red.frame(width: 40, height: 40).zIndex(1).opacity(1)
            Color.blue.frame(width: 40, height: 40).zIndex(1)
        })
        #expect(ties == ["fillRect(80, 30, 40, 40) #FF383C", "fillRect(80, 30, 40, 40) #0088FF"])
        // The front-most view takes the tap.
        let counter = Counter()
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100))
        renderer.mount(ZStack {
            Color.red.frame(width: 100, height: 100).onTapGesture { counter.taps += 10 }.zIndex(1)
            Color.blue.frame(width: 100, height: 100).onTapGesture { counter.taps += 1 }
        })
        renderer.renderFrame()
        renderer.runtime.pointerDown(at: CGPoint(x: 100, y: 50))
        renderer.runtime.pointerUp(at: CGPoint(x: 100, y: 50))
        #expect(counter.taps == 10)
    }

    /// Apple's rasteriser on (204, 102, 51) (`effects/brightness`, `effects/saturation`,
    /// `effects/color-map`, 2026-09-04).
    @Test func colorMatricesMatchTheMeasuredPixels() {
        let orange = RGBA(r: 204, g: 102, b: 51)
        // Within one 8-bit step of the golden (Apple rounds exact halves down).
        func matches(_ matrix: ColorMatrix, _ expected: [Int], _ color: RGBA = orange) -> Bool {
            let out = matrix.apply(color)
            let bytes = [out.red, out.green, out.blue, out.alpha].map { Int(($0 * 255).rounded()) }
            return zip(bytes, expected).allSatisfy { abs($0 - $1) <= 1 }
        }
        #expect(matches(.brightness(0.2), [255, 153, 102, 255]))
        #expect(matches(.brightness(-0.3), [127, 25, 0, 255]))
        #expect(matches(.contrast(0.5), [166, 115, 89, 255]))
        #expect(matches(.contrast(1.5), [242, 89, 13, 255]))
        #expect(matches(.contrast(2), [255, 76, 0, 255]))
        #expect(matches(.saturation(0), [120, 120, 120, 255]))
        #expect(matches(.saturation(0.5), [162, 111, 85, 255]))
        #expect(matches(.saturation(2), [255, 84, 0, 255]))
        #expect(matches(.hueRotation(.degrees(90)), [51, 149, 36, 255]))
        #expect(matches(.hueRotation(.degrees(200)), [65, 127, 213, 255]))
        #expect(matches(.invert, [51, 153, 204, 255]))
        #expect(matches(.multiply(RGBA(red: 0, green: 0.5, blue: 1)), [0, 51, 51, 255]))
        #expect(matches(.multiply(RGBA(red: 1, green: 1, blue: 1, alpha: 0.5)), [204, 102, 51, 128]))
        #expect(matches(.luminanceToAlpha, [0, 0, 0, 120]))
        // luminanceToAlpha replaces the content's alpha rather than scaling it.
        #expect(matches(.luminanceToAlpha, [0, 0, 0, 120], orange.multiplyingAlpha(by: 0.5)))
        // Premultiplied pixels: un-premultiplied, transformed, premultiplied again.
        var pixels: [UInt8] = [102, 51, 26, 128, 204, 102, 51, 255]
        pixels.withUnsafeMutableBufferPointer { ColorMatrix.invert.apply(toPremultiplied: $0) }
        #expect(pixels == [26, 77, 102, 128, 51, 153, 204, 255])
    }

    @Test func colorEffectsWrapTheContentInFilterGroups() {
        let box = Color.red.frame(width: 20, height: 10)
        #expect(render(box.colorInvert()) == ["beginFilter(colorMatrix(-1 0 0 0 1 0 -1 0 0 1 0 0 -1 0 1 0 0 0 1 0)(90, 45, 20, 10))", "fillRect(90, 45, 20, 10) #FF383C", "endGroup"])
        #expect(render(box.brightness(0.25)).first == "beginFilter(colorMatrix(1 0 0 0 0.25 0 1 0 0 0.25 0 0 1 0 0.25 0 0 0 1 0)(90, 45, 20, 10))")
        // grayscale is the complementary saturation; identity matrices paint no group.
        #expect(render(box.grayscale(0.5)) == render(box.saturation(0.5)))
        #expect(render(box.saturation(1)) == ["fillRect(90, 45, 20, 10) #FF383C"])
        #expect(render(box.brightness(0)) == ["fillRect(90, 45, 20, 10) #FF383C"])
        // Chained effects nest, innermost first.
        let chain = render(box.saturation(0).brightness(0.2))
        #expect(chain.count == 5 && chain[0].hasPrefix("beginFilter(colorMatrix(1 0 0 0 0.2") && chain[1].hasPrefix("beginFilter(colorMatrix(0.2126"))
        // Blur: a soft blur paints outside the frame, an opaque one keeps its edges; zero is plain.
        #expect(render(box.blur(radius: 3)) == ["beginFilter(blur(3)(90, 45, 20, 10))", "fillRect(90, 45, 20, 10) #FF383C", "endGroup"])
        #expect(render(box.blur(radius: 3, opaque: true)).first == "beginFilter(blur(3 opaque)(90, 45, 20, 10))")
        #expect(render(box.blur(radius: 0)) == ["fillRect(90, 45, 20, 10) #FF383C"])
        // Blend modes; normal paints plainly.
        #expect(render(box.blendMode(.multiply)) == ["beginBlend(multiply(90, 45, 20, 10))", "fillRect(90, 45, 20, 10) #FF383C", "endGroup"])
        #expect(render(box.blendMode(.normal)) == ["fillRect(90, 45, 20, 10) #FF383C"])
        // Layout is untouched.
        let runtime = Runtime()
        runtime.mount(HStack(spacing: 0) { box.blur(radius: 10); box.colorInvert(); box.blendMode(.screen) })
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.render(scale: 2).commands.filter { $0.description.hasPrefix("fillRect") }.map(\.description) == ["fillRect(70, 45, 20, 10) #FF383C", "fillRect(90, 45, 20, 10) #FF383C", "fillRect(110, 45, 20, 10) #FF383C"])
    }

    @Test func filterAndBlendGroupsEncodeAndDecode() {
        var list = DisplayList()
        list.append(.beginFilter(.blur(radius: 2.5, opaque: true), bounds: CGRect(x: 1, y: 2, width: 3, height: 4)))
        list.append(.endGroup)
        list.append(.beginFilter(.colorMatrix(.invert), bounds: CGRect(x: 0, y: 0, width: 10, height: 10)))
        list.append(.endGroup)
        list.append(.beginBlend(.plusLighter, bounds: CGRect(x: 5, y: 6, width: 7, height: 8)))
        list.append(.endGroup)
        let decoded = DisplayListDecoder.decode(DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont))
        #expect(decoded[0] == "beginFilter 1.0,2.0,3.0,4.0 blur 2.5 opaque")
        #expect(decoded[2] == "beginFilter 0.0,0.0,10.0,10.0 matrix [-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]")
        #expect(decoded[4] == "beginBlend 20 5.0,6.0,7.0,8.0")
        #expect(BlendMode.allCases.map(\._index) == Array(0..<21))
    }

    @Test func gaussianBlurSpreadsSoftEdgesAndKeepsOpaqueOnes() {
        // A 12 × 12 bitmap with an opaque black band in columns 4…7; the middle row has full
        // vertical support, so it reads as a one-dimensional profile.
        let width = 12, height = 12
        var soft = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 4..<8 { soft[(y * width + x) * 4 + 3] = 255 } }
        var opaque = soft
        soft.withUnsafeMutableBufferPointer { PixelFilters.gaussianBlur($0, width: width, height: height, sigma: 1, keepAlpha: false) }
        opaque.withUnsafeMutableBufferPointer { PixelFilters.gaussianBlur($0, width: width, height: height, sigma: 1, keepAlpha: true) }
        let row = 6 * width
        let softAlpha = (0..<width).map { Int(soft[(row + $0) * 4 + 3]) }
        // Coverage falls across the edge symmetrically and is gone beyond three sigma.
        #expect(softAlpha[0] == 0 && softAlpha[11] == 0)
        #expect(softAlpha[3] > 30 && softAlpha[3] < 128 && softAlpha[4] > 128 && softAlpha[5] > softAlpha[4])
        #expect(abs(softAlpha[3] - (255 - softAlpha[4])) <= 2)
        #expect(softAlpha == softAlpha.reversed())
        #expect((0..<width).map { Int(opaque[(row + $0) * 4 + 3]) } == (0..<width).map { $0 >= 4 && $0 < 8 ? 255 : 0 })
        // An opaque blur of a uniform colour keeps it uniform right to the edge.
        var colour = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 4..<8 { let o = (y * width + x) * 4; colour[o] = 200; colour[o + 1] = 100; colour[o + 3] = 255 } }
        colour.withUnsafeMutableBufferPointer { PixelFilters.gaussianBlur($0, width: width, height: height, sigma: 2, keepAlpha: true) }
        #expect((4..<8).allSatisfy { colour[(row + $0) * 4] == 200 && colour[(row + $0) * 4 + 1] == 100 && colour[(row + $0) * 4 + 3] == 255 })
        #expect(PixelFilters.gaussianKernel(sigma: 0) == [1])
        #expect(PixelFilters.gaussianKernel(sigma: 2).count == 13)
    }

    @Test func effectsApplyPerElementUnlessAGroupComposites() {
        let pair = ZStack {
            Color.red.frame(width: 40, height: 40).frame(width: 60, alignment: .leading)
            Color.blue.frame(width: 40, height: 40).frame(width: 60, alignment: .trailing)
        }
        // Opacity, shadow, filters and blend modes wrap every element in its own group.
        let opacity = render(pair.opacity(0.5))
        #expect(opacity == ["beginGroup(opacity: 0.5)", "fillRect(70, 30, 40, 40) #FF383C", "endGroup",
                            "beginGroup(opacity: 0.5)", "fillRect(90, 30, 40, 40) #0088FF", "endGroup"])
        #expect(render(pair.shadow(color: .black, radius: 2)).filter { $0.hasPrefix("beginShadow") }.count == 2)
        let inverted = render(pair.colorInvert())
        #expect(inverted.filter { $0.hasPrefix("beginFilter") }.count == 2)
        // Each element's group takes that element's own frame.
        #expect(inverted[0].hasSuffix("(70, 30, 40, 40))") && inverted[3].hasSuffix("(90, 30, 40, 40))"))
        #expect(render(pair.blendMode(.multiply)).filter { $0.hasPrefix("beginBlend") }.count == 2)
        // Nested effects nest per element, outermost first.
        let nested = render(pair.opacity(0.5).colorInvert())
        #expect(nested.prefix(2).map { String($0.prefix(11)) } == ["beginFilter", "beginGroup("])
        // A compositing group (and drawingGroup) collects them into one group over the whole frame.
        let grouped = render(pair.compositingGroup().opacity(0.5))
        #expect(grouped == ["beginGroup(opacity: 0.5)", "fillRect(70, 30, 40, 40) #FF383C", "fillRect(90, 30, 40, 40) #0088FF", "endGroup"])
        #expect(render(pair.drawingGroup().shadow(color: .black, radius: 2)) == ["beginShadow(#000000 r=2 dx=0 dy=0)", "fillRect(70, 30, 40, 40) #FF383C", "fillRect(90, 30, 40, 40) #0088FF", "endGroup"])
        // Without pending effects the group is transparent; a text's background gets its own shadow.
        #expect(render(pair.compositingGroup()) == ["fillRect(70, 30, 40, 40) #FF383C", "fillRect(90, 30, 40, 40) #0088FF"])
        let label = render(Color.red.frame(width: 20, height: 10).padding(5).background(Color.white).shadow(color: .black, radius: 1))
        #expect(label.filter { $0.hasPrefix("beginShadow") }.count == 2)
    }

    @Test func maskShowsTheContentThroughTheMaskAlpha() {
        let commands = render(Color.red.frame(width: 40, height: 20).mask { Color.black.frame(width: 20, height: 20) })
        #expect(commands == ["beginMask(80, 40, 40, 20)", "fillRect(90, 40, 20, 20) #000000", "beginMasked", "fillRect(80, 40, 40, 20) #FF383C", "endGroup"])
        // Alignment places the mask like an overlay; the mask ignores the distributed effects,
        // the content keeps them.
        let aligned = render(Color.red.frame(width: 40, height: 20).mask(alignment: .topLeading) { Color.black.frame(width: 20, height: 10) }.opacity(0.5))
        #expect(aligned == ["beginMask(80, 40, 40, 20)", "fillRect(80, 40, 20, 10) #000000", "beginMasked",
                            "beginGroup(opacity: 0.5)", "fillRect(80, 40, 40, 20) #FF383C", "endGroup", "endGroup"])
        // The deprecated spelling, and layout untouched.
        #expect(render(Color.red.frame(width: 40, height: 20).mask(Circle())).first == "beginMask(80, 40, 40, 20)")
        var list = DisplayList()
        list.append(.beginMask(bounds: CGRect(x: 1, y: 2, width: 3, height: 4)))
        list.append(.beginMasked)
        list.append(.endGroup)
        #expect(DisplayListDecoder.decode(DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)) == ["beginMask 1.0,2.0,3.0,4.0", "beginMasked", "endGroup"])
    }

    @Test func hiddenKeepsLayoutAndDrawsNothing() {
        let commands = render(VStack(spacing: 0) {
            Color.red.frame(width: 20, height: 10)
            Color.blue.frame(width: 20, height: 10).hidden()
            Color.green.frame(width: 20, height: 10)
        })
        #expect(commands == ["fillRect(90, 35, 20, 10) #FF383C", "fillRect(90, 55, 20, 10) #34C759"])
        // Not hit tested, absent from semantics.
        let counter = Counter()
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100))
        renderer.mount(ZStack {
            Color.blue.frame(width: 100, height: 100).onTapGesture { counter.taps += 1 }
            Button("Ghost") { counter.taps += 100 }.hidden()
        })
        renderer.renderFrame()
        #expect(!renderer.runtime.semanticsTree().contains { $0.label == "Ghost" })
        renderer.runtime.pointerDown(at: CGPoint(x: 100, y: 50))
        renderer.runtime.pointerUp(at: CGPoint(x: 100, y: 50))
        #expect(counter.taps == 1)
    }
}
#endif
