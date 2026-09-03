// Form (Phase 2): the columns layout (label column, control column, row spacing), the grouped
// cards, and control rows in both. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct FormTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Name", 35.5), ("Enabled", 49.0), ("Count", 36.5), ("Hello", 33.0), ("Save", 29.5), ("Plain", 29.5), ("Apple", 35.0), ("Banana", 45.0), ("Fruit", 28.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 360, height: 300)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    @Test func columnsAlignControlsAfterTheWidestLabel() {
        let r = runtime(Form {
            TextField("Name", text: .constant("Hello"))._probe("field")
            Toggle("Enabled", isOn: .constant(true))._probe("toggle")
            Stepper("Count", value: .constant(1))._probe("stepper")
            Button("Save") {}._probe("button")
            Text("Plain")._probe("text")
        }._probe("form"))
        // The control column starts at the widest label ("Count" 36.5) + 8 = 44.5; the field row is
        // proposed its label + the column's width and fills to the trailing edge.
        let form = r.probeFrames["form"]!
        #expect(form.width == 360)
        #expect(r.probeFrames["field"]?.minX == 1)
        #expect(r.probeFrames["field"]?.maxX == 360)
        #expect(r.probeFrames["toggle"]?.minX == 44.5)
        #expect(r.probeFrames["stepper"]?.minX == 0)
        #expect(r.probeFrames["button"]?.minX == 44.5)
        #expect(r.probeFrames["text"]?.minX == 44.5)
        // Rows: 6 under a text field, 8.15 under a stepper (the text-adjacent gaps need the recorded
        // font spacings; form/basic proves them in Tier A).
        let field = r.probeFrames["field"]!, toggle = r.probeFrames["toggle"]!, stepper = r.probeFrames["stepper"]!
        let button = r.probeFrames["button"]!
        #expect(toggle.minY - field.maxY == 6)
        #expect(abs(button.minY - stepper.maxY - 8.15087890625) < 1e-9)
    }

    @Test func columnsFormWithoutLabelsIsContentSized() {
        let r = runtime(Form { Toggle("Enabled", isOn: .constant(true))._probe("toggle") }.frame(width: 200, height: 100)._probe("frame"))
        // No label column: the toggle is the form, centred by the frame.
        #expect(r.probeFrames["toggle"] == CGRect(x: 80 + (200 - 70) / 2, y: 100 + (100 - 18.5) / 2, width: 70, height: 18.5))
    }

    @Test func groupedCardsAndRows() {
        let r = runtime(Form {
            TextField("Name", text: .constant("Hello"))._probe("field")
            Toggle("Enabled", isOn: .constant(true))._probe("toggle")
        }.formStyle(.grouped).frame(height: 110)._probe("form"), size: CGSize(width: 360, height: 110))
        // Inset 20: rows 300 wide at x = 30, the label's 18.5 tall, 10 pt padding, 1 pt separator.
        #expect(r.probeFrames["form"] == CGRect(x: 0, y: 0, width: 360, height: 110))
        #expect(r.probeFrames["field"] == CGRect(x: 30, y: 30, width: 300, height: 18.5))
        #expect(r.probeFrames["toggle"] == CGRect(x: 30, y: 69.5, width: 300, height: 18.5))
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains("fillRRect(20, 20, 320, 78) r=10 #000000@\(8.0 / 255)"))
        #expect(commands.contains("fillRect(30, 58.5, 300, 1) #000000@\(20.0 / 255)"))
        // The text field is borderless and right-aligned; the toggle is a small switch at the trailing edge.
        #expect(commands.contains { $0.hasPrefix("drawText(\"Hello\" system 13 w400 at 297,") })
        #expect(commands.contains { $0.hasPrefix("fillRRect(294, ") && $0.contains("36, 16") })
    }
}
#endif
