// Phase 1 step 7: display lists for colours, shapes, text, background/overlay, opacity, clipping.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PaintTests {
    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100), scale: CGFloat = 2) -> [String] {
        let runtime = Runtime()
        let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: body, width: nil, string: "Hello"): .init(width: 31, height: 18.5, firstBaseline: 14, lastBaseline: 14),
        ])
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime.render(scale: scale).commands.map(\.description)
    }

    @Test func colorFillsItsPixelAlignedFrame() {
        #expect(render(Color.red.frame(width: 50, height: 30)) == ["fillRect(75, 35, 50, 30) #FF383C"])
        // 84.5 is on the half-pixel grid at 2×; 40.75 rounds to 41 (edges round independently).
        #expect(render(Color.blue.frame(width: 31, height: 18.5)) == ["fillRect(84.5, 41, 31, 18.5) #0088FF"])
        #expect(render(Color.blue.frame(width: 31, height: 18.5), scale: 1) == ["fillRect(85, 41, 31, 18) #0088FF"])
        #expect(render(Color.clear.frame(width: 10, height: 10)).isEmpty)
        #expect(render(Color(red: 0.2, green: 0.4, blue: 0.6).opacity(0.5).frame(width: 10, height: 10)) == ["fillRect(95, 45, 10, 10) #336699@0.5"])
    }

    @Test func textDrawsAtBaseline() {
        #expect(render(Text("Hello")) == ["drawText(\"Hello\" system 13 w400 at 84.5,55 #000000@0.85)"])
        #expect(render(Text("Hello").foregroundColor(.red)) == ["drawText(\"Hello\" system 13 w400 at 84.5,55 #FF383C)"])
        #expect(render(Text("Hello").foregroundStyle(.blue)) == ["drawText(\"Hello\" system 13 w400 at 84.5,55 #0088FF)"])
    }

    @Test func shapesFillAndStroke() {
        #expect(render(Rectangle().fill(Color.red).frame(width: 20, height: 10)) == ["fillRect(90, 45, 20, 10) #FF383C"])
        #expect(render(Rectangle().frame(width: 20, height: 10)) == ["fillRect(90, 45, 20, 10) #000000@0.85"])
        #expect(render(RoundedRectangle(cornerRadius: 4).fill(Color.green).frame(width: 20, height: 10)) == ["fillRRect(90, 45, 20, 10) r=4 #34C759"])
        #expect(render(Capsule().fill(Color.green).frame(width: 20, height: 10)) == ["fillRRect(90, 45, 20, 10) r=5 #34C759"])
        #expect(render(Circle().fill(Color.blue).frame(width: 20, height: 10)) == ["fillPath(6 elements) #0088FF"])
        #expect(render(Circle().stroke(Color.blue, lineWidth: 2).frame(width: 20, height: 20)) == ["strokePath(6 elements) w=2 #0088FF"])
        // A circle takes the smaller dimension of its share; the ellipse gets what is left.
        let runtime = Runtime()
        runtime.mount(HStack(spacing: 0) { Circle()._probe("c"); Ellipse()._probe("e") })
        runtime.layout(in: CGSize(width: 100, height: 40))
        #expect(runtime.probeFrames["c"] == CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(runtime.probeFrames["e"] == CGRect(x: 40, y: 0, width: 60, height: 40))
    }

    @Test func backgroundAndOverlayOrderAndAlignment() {
        let commands = render(
            Color.red.frame(width: 100, height: 60)
                .background(Color.blue.frame(width: 20, height: 20), alignment: .bottomTrailing)
                .overlay(alignment: .topLeading) { Color.green.frame(width: 10, height: 10) })
        #expect(commands == [
            "fillRect(130, 60, 20, 20) #0088FF",
            "fillRect(50, 20, 100, 60) #FF383C",
            "fillRect(50, 20, 10, 10) #34C759",
        ])
        // A style background fills the content's frame.
        #expect(render(Color.red.frame(width: 20, height: 10).padding(5).background(.yellow)) == [
            "fillRect(85, 40, 30, 20) #FFCC00",
            "fillRect(90, 45, 20, 10) #FF383C",
        ])
        #expect(render(Color.red.frame(width: 20, height: 10).background(.blue, in: RoundedRectangle(cornerRadius: 3))) == [
            "fillRRect(90, 45, 20, 10) r=3 #0088FF",
            "fillRect(90, 45, 20, 10) #FF383C",
        ])
    }

    @Test func opacityAndClipping() {
        #expect(render(Color.red.frame(width: 20, height: 10).opacity(0.5)) == [
            "beginGroup(opacity: 0.5)", "fillRect(90, 45, 20, 10) #FF383C", "endGroup",
        ])
        #expect(render(Color.red.frame(width: 20, height: 10).opacity(0)).isEmpty)
        #expect(render(Color.red.frame(width: 20, height: 10).opacity(1)) == ["fillRect(90, 45, 20, 10) #FF383C"])
        #expect(render(Color.red.frame(width: 20, height: 10).clipShape(RoundedRectangle(cornerRadius: 4))) == [
            "save", "clipRRect(90, 45, 20, 10) r=4", "fillRect(90, 45, 20, 10) #FF383C", "restore",
        ])
        #expect(render(Color.red.frame(width: 20, height: 10).clipped()) == [
            "save", "clipRect(90, 45, 20, 10)", "fillRect(90, 45, 20, 10) #FF383C", "restore",
        ])
        #expect(render(Color.red.frame(width: 20, height: 10).clipShape(Circle())) == [
            "save", "clipPath(6 elements)", "fillRect(90, 45, 20, 10) #FF383C", "restore",
        ])
    }

    @Test func stacksPaintInOrderWithAbsoluteCoordinates() {
        let commands = render(VStack(spacing: 0) {
            Color.red.frame(width: 20, height: 10)
            HStack(spacing: 0) {
                Color.green.frame(width: 10, height: 10)
                Color.blue.frame(width: 10, height: 10)
            }
        })
        #expect(commands == [
            "fillRect(90, 40, 20, 10) #FF383C",
            "fillRect(90, 50, 10, 10) #34C759",
            "fillRect(100, 50, 10, 10) #0088FF",
        ])
    }

    @Test func pathPrimitives() {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 5))
        path.addLine(to: CGPoint(x: 0, y: 5))
        path.closeSubpath()
        #expect(path.asRect == CGRect(x: 0, y: 0, width: 10, height: 5))
        #expect(Path(CGRect(x: 1, y: 2, width: 3, height: 4)).boundingRect == CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10)).elements.count == 6)
        #expect(Path(roundedRect: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 2).elements.count == 10)
        #expect(path.offsetBy(dx: 1, dy: 1).asRect == CGRect(x: 1, y: 1, width: 10, height: 5))
    }
}
#endif
