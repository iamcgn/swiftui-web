// Safe-area corners (sw-safe-area, Docs/elements/Position.md): a geometry reader under an inset
// reports it and places its content in the safe part, every element of a list gets its own
// inset view, a scroll view's indicator track stops at the inset, the keyboard region is nothing
// in a browser, and a smaller view ignoring the safe area stays centred in the safe frame.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Observable private final class FlashModel: @unchecked Sendable { var flash = 0 }

private struct InsetFlashing: View {
    let model: FlashModel
    var body: some View {
        ScrollView { VStack(spacing: 0) { ForEach(0..<20, id: \.self) { _ in Color.green.frame(height: 30) } } }
            .scrollIndicatorsFlash(trigger: model.flash)
            .safeAreaInset(edge: .bottom) { Color.red.frame(height: 30) }
            .frame(width: 100, height: 200)
    }
}

@Suite @MainActor struct SafeAreaTests {
    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 300, height: 240)) -> Runtime {
        let r = Runtime()
        r.mount(view)
        r.layout(in: size)
        return r
    }

    @Test func geometryReadersReportTheInset() {
        let r = runtime(GeometryReader { proxy in
            Color.red.frame(width: max(1, proxy.safeAreaInsets.leading), height: max(1, proxy.safeAreaInsets.bottom))._probe("child")
        }
        .safeAreaInset(edge: .bottom) { Color.blue.frame(height: 30) }
        .safeAreaInset(edge: .leading) { Color.blue.frame(width: 20) }
        .frame(width: 100, height: 200)._probe("reader"))
        // The reader fills the frame; its content sits at the safe region's origin (28 in from
        // the leading inset of 20 + 8) and the proxy reports the two insets (28 and 38).
        #expect(r.probeFrames["reader"]?.size == CGSize(width: 100, height: 200))
        #expect(r.probeFrames["child"] == CGRect(x: 100 + 28, y: 20, width: 28, height: 38))
        // Ignoring the safe area, the reader reports none.
        let ignoring = runtime(GeometryReader { proxy in Color.red.frame(width: max(1, proxy.safeAreaInsets.bottom), height: 10)._probe("none") }.ignoresSafeArea()
            .safeAreaInset(edge: .bottom) { Color.blue.frame(height: 30) }.frame(width: 100, height: 200))
        #expect(ignoring.probeFrames["none"]?.width == 1)
    }

    @Test func insetsApplyPerListElement() {
        let r = runtime(VStack(spacing: 0) {
            ForEach(["a", "b", "c"], id: \.self) { Color.green.frame(height: 20)._probe($0) }
                .safeAreaInset(edge: .bottom, spacing: 2) { Color.red.frame(height: 6)._probe("bar") }
        }.frame(width: 100)._probe("stack"))
        // Three rows of 20 + 6 + 2: the stack is 84 tall, the rows 28 apart; three bars painted.
        #expect(r.probeFrames["stack"]?.height == 84)
        #expect(r.probeFrames["b"]!.minY - r.probeFrames["a"]!.minY == 28 && r.probeFrames["c"]!.minY - r.probeFrames["b"]!.minY == 28)
        let bars = r.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillRect(") && $0.split(separator: ")")[0].hasSuffix(", 6") }
        #expect(bars.count == 3, "\(r.render(scale: 2).commands.map(\.description))")
    }

    @Test func indicatorTrackStopsAtTheInset() {
        let model = FlashModel()
        let r = Runtime()
        r.mount(InsetFlashing(model: model))
        r.layout(in: CGSize(width: 100, height: 200))
        model.flash += 1
        r.layout(in: CGSize(width: 100, height: 200))
        let knobs = r.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillRRect") && $0.contains("@") }
        // The content is 600 in a 200 viewport whose bottom 38 are under the bar: the track is
        // 200 − 8 − 38 = 154, the knob 154 × 200 / 638 ≈ 48.3 (not 60 of a full track).
        let core = knobs.last!
        let numbers = core.split(separator: "(", maxSplits: 1)[1].split(separator: ")")[0].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        #expect(abs(numbers[3] - 154 * 200 / 638) < 0.5, "\(core)")   // the knob is drawn to the half point
        #expect(numbers[1] == 4, "the knob starts 4 from the top: \(core)")
    }

    @Test func smallerIgnoringContentStaysCentredInTheSafeFrame() {
        // Measured on macOS 26.6: a 50 pt stack ignoring the safe area under a bottom inset sits at
        // (82 − 50) / 2 from the top of the 100 pt frame, the stack 50 tall; a filling stack takes 100.
        let r = runtime(HStack(spacing: 0) {
            VStack { Color.blue.frame(height: 50) }.ignoresSafeArea()._probe("small")
                .safeAreaInset(edge: .bottom) { Color.red.frame(height: 10) }.frame(width: 60, height: 100)
            VStack { Color.blue._probe("fillInner") }.ignoresSafeArea()._probe("fill")
                .safeAreaInset(edge: .bottom) { Color.red.frame(height: 10) }.frame(width: 60, height: 100)
        }._probe("row"), size: CGSize(width: 120, height: 100))
        #expect(r.probeFrames["small"]?.minY == 16 && r.probeFrames["small"]?.height == 50)
        #expect(r.probeFrames["fill"]?.height == 82 && r.probeFrames["fillInner"]?.height == 100)
        // The keyboard region exists only to be accepted: ignoring it changes nothing.
        let keyboard = runtime(Color.blue.ignoresSafeArea(.keyboard)._probe("k").safeAreaInset(edge: .bottom) { Color.red.frame(height: 10) }.frame(width: 60, height: 100))
        #expect(keyboard.probeFrames["k"]?.height == 82)
    }
}
#endif
