// The iOS 18 and 26 symbol effects (ButtonKit, CriticalMaps; Packages/Shadows' Symbols module
// re-exports them on wasm): effects are
// Sendable and Hashable values a Sendable style can hold, draw on and draw off fade the symbol
// in and out as appear and disappear do, and the magic replace is a content transition.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct SymbolEffectTypesTests {
    /// ButtonKit's `SymbolEffectAsyncButtonStyle`: a Sendable style that holds its effect.
    struct Style<Effect: SymbolEffect & IndefiniteSymbolEffect>: Sendable {
        let effect: Effect
    }

    @Observable final class Model: @unchecked Sendable {
        var loading = false
    }

    struct Drawing: View {
        let model: Model
        var body: some View {
            HStack {
                Image(systemName: "star").symbolEffect(.drawOff, isActive: model.loading)
                Image(systemName: "heart").symbolEffect(.drawOn.byLayer, isActive: model.loading)
                Image(systemName: "bell").contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
            }
        }
    }

    @Test func effectsAreValues() {
        let styles: [Style<DrawOffSymbolEffect>] = [Style(effect: .drawOff), Style(effect: .drawOff.individually)]
        #expect(styles.count == 2)
        #expect(Set([AnyHashable(BounceSymbolEffect.bounce.up), AnyHashable(BounceSymbolEffect.bounce.down)]).count == 2)
        _ = Style(effect: PulseSymbolEffect.pulse)
    }

    @Test func drawOnAndOffFadeTheSymbol() {
        let model = Model()
        let runtime = Runtime()
        runtime.mount(Drawing(model: model))
        let size = CGSize(width: 200, height: 100)
        runtime.layout(in: size)
        func opacities() -> [String] { runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("beginGroup(opacity:") } }
        #expect(opacities().isEmpty)
        model.loading = true
        runtime.layout(in: size)
        #expect(runtime.advanceAnimations(elapsed: 1))
        #expect(opacities() == ["beginGroup(opacity: 0.0)"])   // the star drawn off, the heart drawn on
    }

    /// ButtonKit's and IceCubes' calls: labels and buttons from an image resource, a drag from
    /// an item provider.
    struct Resources: View {
        var body: some View {
            VStack {
                Label("Save", image: ImageResource(name: "disk", bundle: .main))
                Button("Send", image: ImageResource(name: "plane", bundle: .main)) {}
                Text("Drag me").onDrag { NSItemProvider(object: "a" as NSString) }
            }
        }
    }

    @Test func imageResourcesAndDragsMount() {
        let runtime = Runtime()
        runtime.textEngine = MonospaceTextEngine()
        runtime.mount(Resources())
        runtime.layout(in: CGSize(width: 300, height: 200))
        let texts = runtime.render(scale: 1).commands.map(\.description).filter { $0.hasPrefix("drawText(") }
        #expect(["Save", "Send", "Drag me"].allSatisfy { word in texts.contains { $0.hasPrefix("drawText(\"\(word)\"") } }, "\(texts)")
    }
}
#endif
