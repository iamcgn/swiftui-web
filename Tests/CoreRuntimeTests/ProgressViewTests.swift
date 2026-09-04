// ProgressView: bar and ring sizes, the completed fraction's fill, labels and value labels,
// styles, control sizes and the indeterminate looks. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ProgressViewTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Loading", 50.0), ("30%", 26.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    private func commands<V: View>(_ view: V) -> [String] { runtime(view).render(scale: 2).commands.map(\.description) }

    @Test func linearBars() {
        // The bar row is 20 tall and as wide as proposed; the 8 pt pill fills the fraction.
        let r = runtime(ProgressView(value: 0.4)._probe("bar"))
        #expect(r.probeFrames["bar"] == CGRect(x: 0, y: 40, width: 200, height: 20))
        let bar = r.render(scale: 2).commands.map(\.description)
        #expect(bar == ["fillRRect(0, 46, 200, 8) r=4 #000000@\(15.0 / 255)", "fillRRect(0, 46, 80, 8) r=4 #000000@\(85.0 / 255)"])
        // `total` scales the value; a narrow frame narrows the bar; nothing is filled at zero.
        #expect(commands(ProgressView(value: 25, total: 50).frame(width: 120)).last == "fillRRect(40, 46, 60, 8) r=4 #000000@\(85.0 / 255)")
        #expect(commands(ProgressView(value: 0)).count == 1)
        // A label sits above the row, a current value label (secondary) under it.
        let labelled = runtime(ProgressView(value: 0.3) { Text("Loading")._probe("label") } currentValueLabel: { Text("30%")._probe("value") }._probe("whole"))
        #expect(labelled.probeFrames["whole"] == CGRect(x: 0, y: 24, width: 200, height: 52))
        #expect(labelled.probeFrames["label"] == CGRect(x: 0, y: 24, width: 50, height: 16))
        #expect(labelled.probeFrames["value"] == CGRect(x: 0, y: 60, width: 26, height: 16))
        #expect(labelled.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"30%\"") && $0.hasSuffix("#000000@0.5)") })
        // An indeterminate bar shows a short segment at the start.
        #expect(commands(ProgressView().progressViewStyle(.linear)).last == "fillRRect(0, 46, 8, 8) r=4 #000000@\(85.0 / 255)")
    }

    @Test func ringsAndSpinners() {
        // A determinate ring is 32 pt: a 5 pt track and the fraction's arc from the top.
        let r = runtime(ProgressView(value: 0.25).progressViewStyle(.circular)._probe("ring"))
        #expect(r.probeFrames["ring"] == CGRect(x: 84, y: 34, width: 32, height: 32))
        let ring = r.render(scale: 2).commands.map(\.description)
        #expect(ring.count == 2 && ring[0].contains("w=5 #000000@\(13.0 / 255)") && ring[1].contains("w=5 cap=round #000000@\(70.0 / 255)"))
        // A full ring has no caps; a label below takes the stack's default spacing (8 with the
        // recorded test engine, which has no font spacing; the golden shows the font's 4.74).
        #expect(commands(ProgressView(value: 1).progressViewStyle(.circular))[1].contains("w=5 #000000@"))
        let labelled = runtime(ProgressView("Loading", value: 0.5).progressViewStyle(.circular)._probe("whole"))
        #expect(abs((labelled.probeFrames["whole"]?.height ?? 0) - 56) < 1e-9)
        // The spinner: eight spokes, fading; the control size scales it.
        let spinner = commands(ProgressView())
        #expect(spinner.count == 8 && spinner.allSatisfy { $0.hasPrefix("strokePath(2 elements) w=3 cap=round") })
        #expect(runtime(ProgressView().controlSize(.small)._probe("s")).probeFrames["s"]?.size == CGSize(width: 16, height: 16))
        #expect(commands(ProgressView().controlSize(.small)).first?.contains("w=1.5") == true)
    }
}
#endif
