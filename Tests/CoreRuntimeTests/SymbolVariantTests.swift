// Symbol variants and rendering modes: candidate names, resolution to measured symbols, the
// environment's accumulation and reset, and rendering modes accepted without effect.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct SymbolVariantTests {
    private func frame<V: View>(_ view: V) -> CGRect? {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime.probeFrames["symbol"]
    }

    @Test func candidateNamesGoFromMostToLeastSpecific() {
        #expect(SymbolVariants.fill.names(for: "star") == ["star.fill", "star"])
        #expect(SymbolVariants.circle.fill.names(for: "person") == ["person.circle.fill", "person.circle", "person.fill", "person"])
        #expect(SymbolVariants.slash.circle.fill.names(for: "bell").first == "bell.slash.circle.fill")
        #expect(SymbolVariants.slash.circle.fill.names(for: "bell").last == "bell")
        #expect(SymbolVariants.none.names(for: "star.fill") == ["star.fill"])
        #expect(SymbolVariants.circle.fill.contains(.fill) && !SymbolVariants.fill.contains(.circle))
        #expect(SymbolVariants.circle.union(.fill) == SymbolVariants.circle.fill)
    }

    @Test func variantsResolveToMeasuredSymbolsAndAccumulate() {
        // star.fill and star have the same measured size, star.circle is smaller (measured).
        let plain = frame(Image(systemName: "star")._probe("symbol"))
        let circle = frame(Image(systemName: "star").symbolVariant(.circle)._probe("symbol"))
        #expect(plain?.size == CGSize(width: 16.5, height: 16) && circle?.size == CGSize(width: 15, height: 15))
        // Ancestors' variants accumulate; .none resets; an unknown variant keeps the base symbol.
        let nested = frame(Image(systemName: "star").symbolVariant(.fill)._probe("symbol").symbolVariant(.circle))
        #expect(nested?.size == CGSize(width: 15, height: 15))
        let reset = frame(Image(systemName: "star").symbolVariant(.none)._probe("symbol").symbolVariant(.circle))
        #expect(reset?.size == CGSize(width: 16.5, height: 16))
        let unknown = frame(Image(systemName: "star").symbolVariant(.rectangle)._probe("symbol"))
        #expect(unknown?.size == CGSize(width: 16.5, height: 16))
        var environment = EnvironmentValues()
        environment.symbolVariants = .circle
        environment.symbolRenderingMode = .hierarchical
        #expect(environment.symbolVariants == .circle && environment.symbolRenderingMode == .hierarchical)
        // Rendering modes and multi-style foregrounds are accepted and keep the first colour.
        let runtime = Runtime()
        runtime.mount(Image(systemName: "star.fill").symbolRenderingMode(.palette).foregroundStyle(Color.red, Color.blue))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("fillPath") && $0.contains("#FF383C") })
    }
}
#endif
