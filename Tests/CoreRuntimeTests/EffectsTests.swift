// Phase 6: shadow (a shadow group in the display list), zIndex (paint order and hit testing) and
// hidden (layout kept, nothing painted, hit tested or exposed).
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
