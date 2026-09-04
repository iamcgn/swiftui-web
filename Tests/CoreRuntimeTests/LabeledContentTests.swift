// LabeledContent: the label/content row, hidden labels, the form's label column, custom styles.
// Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct LabeledContentTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Name", 35.5), ("Corey", 36.0), ("Count", 36.5), ("3", 8.5)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func rows() {
        // Label (body font), 8, content, centred vertically in the body line.
        let r = runtime(LabeledContent("Name") { Text("Corey")._probe("value") }._probe("row"))
        #expect(r.probeFrames["row"]?.size == CGSize(width: 35.5 + 8 + 36, height: 18.5))
        #expect(r.probeFrames["value"] == CGRect(x: (200 - 79.5) / 2 + 35.5 + 8, y: 40.75 + 1.25, width: 36, height: 16))
        // The string value initializer; a hidden label leaves the content alone.
        #expect(abs((runtime(LabeledContent("Count", value: "3")._probe("row")).probeFrames["row"]?.width ?? 0) - 53) < 1e-9)
        #expect(runtime(LabeledContent("Count", value: "3").labelsHidden()._probe("row")).probeFrames["row"]?.size == CGSize(width: 8.5, height: 16))
        // A given width centres the pair.
        let narrow = runtime(LabeledContent("Name", value: "Corey").frame(width: 160)._probe("row"))
        #expect(narrow.probeFrames["row"]?.width == 160)
    }

    struct StackedStyle: LabeledContentStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 0) { configuration.label; configuration.content }
        }
    }

    @Test func customStyleAndForm() {
        let stacked = runtime(LabeledContent("Name", value: "Corey").labeledContentStyle(StackedStyle())._probe("row"))
        #expect(stacked.probeFrames["row"]?.size == CGSize(width: 36, height: 32))
        // In a columns form the label sits in the label column, the content 8 after it.
        let form = runtime(Form { LabeledContent("Name") { Text("Corey")._probe("value") }._probe("row") })
        let row = form.probeFrames["row"]!, value = form.probeFrames["value"]!
        #expect(value.minX == row.minX + 35.5 + 8 && row.height == 16)
    }
}
#endif
