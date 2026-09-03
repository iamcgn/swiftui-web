// Picker, Slider and Stepper (Phase 2): geometry per style, selection by press, slider presses
// and drags, stepper presses, disabled state. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ControlTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    static let footnote = ResolvedFont(family: "system", size: 10, weight: .regular, italic: false, textStyle: .footnote)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Apple", 35.0), ("Banana", 45.0), ("Cherry", 41.5), ("Fruit", 28.0), ("Count", 36.5), ("Volume", 45.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        for (word, width) in [("Min", 17.5), ("Max", 20.0)] {
            entries[RecordedTextEngine.key(font: Self.footnote, width: nil, string: word)] = .init(width: width, height: 15, firstBaseline: 11, lastBaseline: 11)
        }
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }

    @Test func pickerStylesLayOutAndSelect() {
        let box = _IntBox(1)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let menu = runtime(VStack(alignment: .leading, spacing: 12) {
            Picker("Fruit", selection: binding) { Text("Apple").tag(1); Text("Banana").tag(2); Text("Cherry").tag(3) }._probe("menu")
            Picker("Fruit", selection: binding) { Text("Apple").tag(1); Text("Banana").tag(2); Text("Cherry").tag(3) }
                .pickerStyle(.segmented)._probe("segmented")
            Picker("Fruit", selection: binding) { Text("Apple").tag(1)._probe("apple"); Text("Banana").tag(2)._probe("banana") }
                .pickerStyle(.radioGroup)._probe("radio")
        }._probe("stack"))
        // Pop-up: label + 8 + (12 + widest 45 + 35.5) = 128.5 × 24; segmented: 3 × 66; radio rows 18.5 apart by 6.
        #expect(menu.probeFrames["menu"]?.size == CGSize(width: 128.5, height: 24))
        #expect(menu.probeFrames["segmented"]?.size == CGSize(width: 234, height: 24))
        #expect(menu.probeFrames["radio"]?.size == CGSize(width: 102, height: 43))
        let radio = menu.probeFrames["radio"]!
        #expect(menu.probeFrames["apple"] == CGRect(x: radio.minX + 57, y: radio.minY, width: 35, height: 18.5))
        #expect(menu.probeFrames["banana"] == CGRect(x: radio.minX + 57, y: radio.minY + 24.5, width: 45, height: 18.5))
        let painted = commands(menu)
        // The pop-up shows the selected title only; the segmented control paints every title.
        #expect(painted.filter { $0.hasPrefix("drawText(\"Apple\"") }.count == 3)
        #expect(painted.filter { $0.hasPrefix("drawText(\"Cherry\"") }.count == 1)
        // Pressing the second segment and the second radio row select.
        let segmented = menu.probeFrames["segmented"]!
        menu.pointerDown(at: CGPoint(x: segmented.minX + 36 + 99, y: segmented.midY)); menu.pointerUp(at: CGPoint(x: segmented.minX + 36 + 99, y: segmented.midY))
        #expect(box.value == 2)
        menu.pointerDown(at: CGPoint(x: radio.minX + 40, y: radio.minY + 4)); menu.pointerUp(at: CGPoint(x: radio.minX + 40, y: radio.minY + 4))
        #expect(box.value == 1)
        // Options without tags in a ForEach use the ids; a disabled picker ignores presses.
        let disabled = runtime(Picker("Fruit", selection: binding) { ForEach([1, 2], id: \.self) { Text($0 == 1 ? "Apple" : "Banana") } }
            .pickerStyle(.segmented).disabled(true)._probe("p"))
        let p = disabled.probeFrames["p"]!
        disabled.pointerDown(at: CGPoint(x: p.maxX - 10, y: p.midY)); disabled.pointerUp(at: CGPoint(x: p.maxX - 10, y: p.midY))
        #expect(box.value == 1)
    }

    @Test func sliderTrackPressesAndDrags() {
        let box = _DoubleBox(0.5)
        var edits: [Bool] = []
        let r = runtime(Slider(value: Binding(get: { box.value }, set: { box.value = $0 }), in: 0...100, step: 10, onEditingChanged: { edits.append($0) })
            .frame(width: 222)._probe("slider"), size: CGSize(width: 320, height: 100))
        #expect(r.probeFrames["slider"]?.size == CGSize(width: 222, height: 16))
        let slider = r.probeFrames["slider"]!
        // Knob travel is 11 in from each end: pressing at 11 + 200 × 0.75 lands on 80 (stepped by 10).
        r.pointerDown(at: CGPoint(x: slider.minX + 11 + 150, y: slider.midY))
        #expect(box.value == 80)
        r.pointerMoved(to: CGPoint(x: slider.minX + 11 + 200, y: slider.midY))
        #expect(box.value == 100)
        r.pointerMoved(to: CGPoint(x: slider.minX - 50, y: slider.midY))
        #expect(box.value == 0)
        r.pointerUp(at: CGPoint(x: slider.minX - 50, y: slider.midY))
        #expect(edits == [true, false])
        let painted = commands(r)
        // Track, filled part, 11 ticks, knob shadow and knob.
        #expect(painted.filter { $0.hasPrefix("fillRRect") }.count == 2 + 11 + 2)
        // Labels: body label, footnote value labels, pixel-aligned in an 18.5 pt row.
        let labelled = runtime(Slider(value: .constant(0.5)) { Text("Volume") } minimumValueLabel: { Text("Min")._probe("min") } maximumValueLabel: { Text("Max")._probe("max") }
            ._probe("row"), size: CGSize(width: 320, height: 118.5))
        // The row sits at 50; centring would put the 15 pt labels at 51.75, pixel alignment at 52.
        #expect(labelled.probeFrames["row"] == CGRect(x: 0, y: 50, width: 320, height: 18.5))
        #expect(labelled.probeFrames["min"] == CGRect(x: 53, y: 52, width: 17.5, height: 15))
        #expect(labelled.probeFrames["max"] == CGRect(x: 300, y: 52, width: 20, height: 15))
    }

    @Test func stepperPressesStepWithinBounds() {
        let box = _IntBox(9)
        let r = runtime(Stepper("Count", value: Binding(get: { box.value }, set: { box.value = $0 }), in: 0...10, step: 2)._probe("stepper"))
        let stepper = r.probeFrames["stepper"]!
        #expect(stepper.size == CGSize(width: 64.5, height: 26))
        let control = CGPoint(x: stepper.maxX - 10, y: stepper.minY + 6)
        r.pointerDown(at: control); r.pointerUp(at: control)
        #expect(box.value == 10)   // clamped to the range
        let lower = CGPoint(x: stepper.maxX - 10, y: stepper.maxY - 6)
        r.pointerDown(at: lower); r.pointerUp(at: lower)
        #expect(box.value == 8)
        let hidden = runtime(Stepper("Count", value: .constant(1)).labelsHidden()._probe("s"))
        #expect(hidden.probeFrames["s"]?.size == CGSize(width: 20, height: 26))
        var increments = 0
        let closures = runtime(Stepper("Count", onIncrement: { increments += 1 }, onDecrement: nil).disabled(true)._probe("s"))
        let s = closures.probeFrames["s"]!
        closures.pointerDown(at: CGPoint(x: s.maxX - 10, y: s.minY + 6)); closures.pointerUp(at: CGPoint(x: s.maxX - 10, y: s.minY + 6))
        #expect(increments == 0)
    }
}

private final class _IntBox: @unchecked Sendable { var value: Int; init(_ value: Int) { self.value = value } }
private final class _DoubleBox: @unchecked Sendable { var value: Double; init(_ value: Double) { self.value = value } }
#endif
