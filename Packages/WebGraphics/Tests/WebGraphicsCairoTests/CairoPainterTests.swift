// The Cairo painter (pf-linux): a display list rasterised into an image surface comes out with
// the right pixels — fills, rounded corners, paths, strokes, gradients, clips, transforms,
// opacity groups, blend modes, masks and text.
#if canImport(CCairo)
import Testing
import Foundation
import WebGraphics
import WebGraphicsCairo

@Suite @MainActor struct CairoPainterTests {
    private func pixel(_ surface: OpaquePointer, _ x: Int, _ y: Int) -> (Int, Int, Int, Double) {
        let p = CairoPainter.pixel(of: surface, x: x, y: y)
        return (Int((p.red * 255).rounded()), Int((p.green * 255).rounded()), Int((p.blue * 255).rounded()), p.alpha)
    }

    @Test func fillsClipsAndGroups() {
        var list = DisplayList()
        list.append(.fillRect(CGRect(x: 0, y: 0, width: 100, height: 100), RGBA(r: 255, g: 255, b: 255)))
        list.append(.fillRect(CGRect(x: 10, y: 10, width: 30, height: 30), RGBA(r: 255, g: 0, b: 0)))
        list.append(.fillRRect(CGRect(x: 50, y: 10, width: 40, height: 40), cornerRadius: 20, RGBA(r: 0, g: 0, b: 255)))
        list.append(.save)
        list.append(.clipRect(CGRect(x: 0, y: 60, width: 20, height: 40)))
        list.append(.fillRect(CGRect(x: 0, y: 60, width: 100, height: 40), RGBA(r: 0, g: 255, b: 0)))
        list.append(.restore)
        list.append(.beginGroup(opacity: 0.5))
        list.append(.fillRect(CGRect(x: 60, y: 60, width: 30, height: 30), RGBA(r: 0, g: 0, b: 0)))
        list.append(.endGroup)
        let painter = CairoPainter()
        let (surface, width, height) = painter.image(of: list, size: CGSize(width: 100, height: 100), scale: 1)
        #expect(width == 100 && height == 100)
        #expect(pixel(surface, 20, 20) == (255, 0, 0, 1))
        // The rounded rect's corner is outside the circle; its centre is blue.
        #expect(pixel(surface, 70, 30) == (0, 0, 255, 1) && pixel(surface, 51, 11) == (255, 255, 255, 1))
        // The clip keeps the green inside 20 wide.
        #expect(pixel(surface, 10, 80) == (0, 255, 0, 1) && pixel(surface, 40, 80) == (255, 255, 255, 1))
        // Half-opaque black over white is mid grey.
        let grey = pixel(surface, 75, 75)
        #expect(abs(grey.0 - 128) <= 1 && grey.3 == 1, "\(grey)")
        #expect(CairoPainter.writePNG(surface, to: NSTemporaryDirectory() + "cairo-fills.png"))
    }

    @Test func pathsStrokesGradientsAndText() {
        var list = DisplayList()
        list.append(.fillRect(CGRect(x: 0, y: 0, width: 120, height: 80), RGBA(r: 255, g: 255, b: 255)))
        var triangle = Path()
        triangle.move(to: CGPoint(x: 10, y: 70))
        triangle.addLine(to: CGPoint(x: 50, y: 10))
        triangle.addLine(to: CGPoint(x: 90, y: 70))
        triangle.closeSubpath()
        list.append(.fillPath(triangle, RGBA(r: 0, g: 128, b: 0)))
        var line = Path()
        line.move(to: CGPoint(x: 0, y: 75))
        line.addLine(to: CGPoint(x: 120, y: 75))
        list.append(.strokePath(line, style: StrokeStyle(lineWidth: 4), RGBA(r: 0, g: 0, b: 0)))
        let gradient = DisplayGradient(kind: .linear(start: CGPoint(x: 100, y: 0), end: CGPoint(x: 120, y: 0)),
                                       stops: [DisplayGradient.Stop(location: 0, color: RGBA(r: 255, g: 0, b: 0)), DisplayGradient.Stop(location: 1, color: RGBA(r: 0, g: 0, b: 255))])
        list.append(.fillGradient(Path(CGRect(x: 100, y: 0, width: 20, height: 20)), gradient))
        list.append(.drawText("Hi", DisplayFont(ResolvedFont(family: "system", size: 20, weight: FontWeight(700), italic: false, textStyle: nil)), origin: CGPoint(x: 95, y: 60), RGBA(r: 0, g: 0, b: 0)))
        let painter = CairoPainter()
        let (surface, _, _) = painter.image(of: list, size: CGSize(width: 120, height: 80), scale: 2)
        // At scale 2 the pixel grid doubles.
        #expect(pixel(surface, 100, 100) == (0, 128, 0, 1), "inside the triangle")
        #expect(pixel(surface, 20, 40) == (255, 255, 255, 1), "outside it")
        #expect(pixel(surface, 60, 150) == (0, 0, 0, 1), "on the stroke")
        let left = pixel(surface, 201, 10), right = pixel(surface, 238, 10)
        #expect(left.0 > 200 && left.2 < 60 && right.2 > 200 && right.0 < 60, "the gradient runs red to blue: \(left) \(right)")
        // The text put ink somewhere in its box.
        var ink = 0
        for y in 80..<120 { for x in 190..<240 where pixel(surface, x, y).0 < 128 { ink += 1 } }
        #expect(ink > 20, "text drawn: \(ink) dark pixels")
    }

    @Test func blendModesAndMasks() {
        var list = DisplayList()
        list.append(.fillRect(CGRect(x: 0, y: 0, width: 60, height: 60), RGBA(r: 200, g: 200, b: 200)))
        list.append(.beginBlend(.multiply, bounds: CGRect(x: 0, y: 0, width: 60, height: 60)))
        list.append(.fillRect(CGRect(x: 0, y: 0, width: 30, height: 60), RGBA(r: 128, g: 128, b: 128)))
        list.append(.endGroup)
        list.append(.beginMask(bounds: CGRect(x: 30, y: 0, width: 30, height: 60)))
        list.append(.fillRect(CGRect(x: 30, y: 0, width: 30, height: 30), RGBA(r: 0, g: 0, b: 0)))
        list.append(.beginMasked)
        list.append(.fillRect(CGRect(x: 30, y: 0, width: 30, height: 60), RGBA(r: 255, g: 0, b: 0)))
        list.append(.endGroup)
        let painter = CairoPainter()
        let (surface, _, _) = painter.image(of: list, size: CGSize(width: 60, height: 60), scale: 1)
        let multiplied = pixel(surface, 10, 10)
        #expect(abs(multiplied.0 - 100) <= 2, "200 × 128 / 255: \(multiplied)")
        #expect(pixel(surface, 45, 10) == (255, 0, 0, 1), "inside the mask")
        #expect(pixel(surface, 45, 50) == (200, 200, 200, 1), "outside the mask")
    }
}
#endif

#if canImport(CCairo)
@Suite @MainActor struct CairoTextEngineTests {
    @Test func measuresAndWraps() {
        let engine = CairoTextEngine()
        let font = ResolvedFont(family: "system", size: 17, weight: FontWeight(400), italic: false, textStyle: nil)
        let one = engine.layout("Hello", font: font, width: nil)
        #expect(one.lines.count == 1 && one.size.width > 20 && one.size.width < 80, "\(one.size)")
        let wrapped = engine.layout("Hello wrapping world of text", font: font, width: 90)
        #expect(wrapped.lines.count >= 2 && wrapped.size.width <= 90)
        #expect(engine.metrics(for: font).lineHeight > 15)
    }
}
#endif
