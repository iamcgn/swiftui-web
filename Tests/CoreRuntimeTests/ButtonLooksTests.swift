// Phase 8 step 6, sw-button-looks: PrimitiveButtonStyle, control sizes, the destructive and
// disabled looks, the focus ring (Docs/elements/Button.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Counter { var taps = 0 }

/// A primitive style that runs the action on a tap of its own and repeats the label for a
/// destructive role.
private struct Tappable: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            if configuration.role == .destructive { configuration.label }
        }
        .onTapGesture { configuration.trigger() }
    }
}

@Suite @MainActor struct ButtonLooksTests {
    private static let size13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    private static let size10 = ResolvedFont(family: "system", size: 10, weight: .regular, italic: false, textStyle: nil)
    private static let size15 = ResolvedFont(family: "system", size: 15, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (font, height) in [(Self.size13, 16.0), (Self.size10, 12.0), (Self.size15, 18.0)] {
            for word in ["OK", "Delete", "Mini", "Large"] {
                entries[RecordedTextEngine.key(font: font, width: nil, string: word)] = .init(width: 40, height: height, firstBaseline: height - 3, lastBaseline: height - 3)
            }
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 300, height: 200))
        return runtime
    }

    @Test func primitiveStyleOwnsTheInteraction() {
        let counter = Counter()
        let runtime = runtime(Button("Delete", role: .destructive) { counter.taps += 1 }.buttonStyle(Tappable())._probe("button"))
        // No button host: the style's tap gesture runs `trigger`, and the role reaches the style.
        #expect(runtime.root.descendants(where: { $0.nodeDescription == "Button" }).isEmpty)
        #expect(runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("drawText(\"Delete\"") }.count == 2)
        let frame = runtime.probeFrames["button"]!
        runtime.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(counter.taps == 1)
    }

    @Test func controlSizesChangeTheBezel() {
        let runtime = runtime(VStack(spacing: 8) {
            Button("Mini") {}.controlSize(.mini)._probe("mini")
            Button("OK") {}._probe("regular")
            Button("Large") {}.controlSize(.large)._probe("large")
            Button("OK") {}.controlSize(.extraLarge)._probe("extra")
        })
        #expect(runtime.probeFrames["mini"]?.height == 17 && runtime.probeFrames["mini"]?.width == 40 + 16)
        #expect(runtime.probeFrames["regular"]?.height == 24 && runtime.probeFrames["regular"]?.width == 64)
        #expect(runtime.probeFrames["large"]?.height == 32 && runtime.probeFrames["large"]?.width == 64)
        // macOS has no extra large: the regular bezel.
        #expect(runtime.probeFrames["extra"]?.size == runtime.probeFrames["regular"]?.size)
    }

    @Test func destructiveAndDisabledLooks() {
        let runtime = runtime(VStack(spacing: 8) {
            Button("Delete", role: .destructive) {}._probe("destructive")
            Button("Delete", role: .destructive) {}.buttonStyle(.borderedProminent)._probe("prominent")
            Button("OK") {}.disabled(true)._probe("disabled")
            Button("OK") {}.buttonStyle(.plain).disabled(true)._probe("plain")
        })
        let commands = runtime.render(scale: 2).commands.map(\.description)
        let texts = commands.filter { $0.hasPrefix("drawText(") }
        // The destructive labels and the prominent fill are red; the disabled labels dimmed (the
        // bordered one to 30 % of the 85 % label, the plain one to 50 %).
        #expect(texts.count == 4)
        #expect(texts[0].hasSuffix("#FF393B)") && texts[1].hasSuffix("#FFFFFF)"))
        #expect(commands.contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#FF393B") })
        #expect(texts[2].hasSuffix("@0.255)") && commands.contains("beginGroup(opacity: 0.5)"))
    }

    @Test func focusDrawsARing() {
        let runtime = runtime(Button("OK") {}._probe("button"))
        let before = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("strokePath") }.count
        #expect(runtime.moveFocus(forward: true))
        let after = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("strokePath") }.count
        #expect(after == before + 1)
    }
}
#endif
