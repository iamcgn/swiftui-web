// DatePicker: the field's component slots and stepper geometry, the displayed components,
// stepping and component selection (press, keys, range clamping), the field style, the
// calendar's grid, paging and day selection, and the clock. Layout against goldens is in
// GoldenFrameTests.
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct DatePickerTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    static let bold13 = ResolvedFont(family: "system", size: 13, weight: .bold, italic: false, textStyle: nil)
    static let medium13 = ResolvedFont(family: "system", size: 13, weight: .medium, italic: false, textStyle: nil)
    static let bold10 = ResolvedFont(family: "system", size: 10, weight: .bold, italic: false, textStyle: nil)
    static let regular11 = ResolvedFont(family: "system", size: 11, weight: .regular, italic: false, textStyle: nil)
    nonisolated static let utc = TimeZone(identifier: "UTC")!
    /// 15 March 2025, 15:09 UTC.
    nonisolated static let fixed = Date(timeIntervalSinceReferenceDate: 763744140)

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 360, height: 300)) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        func add(_ words: [(String, Double)], _ font: ResolvedFont, height: Double = 16, baseline: Double = 13) {
            for (word, width) in words {
                entries[RecordedTextEngine.key(font: font, width: nil, string: word)] = .init(width: width, height: height, firstBaseline: baseline, lastBaseline: baseline)
            }
        }
        add([("3", 8.5), ("15", 14), ("16", 14), ("2025", 32), ("1", 5.5), ("2026", 32), ("/", 4), (":", 4), (", ", 7.5), (" ", 4), ("PM", 19.5), ("AM", 20),
             ("09", 16.5), ("00", 16), ("12", 14), ("14", 14)] + (1...12).map { ("\($0)", 8.0) }, Self.system13)
        add([("Date", 28.5), ("Calendar", 54.5), ("Clock", 34.5)], Self.body, height: 18.5, baseline: 14)
        add([("Mar 2025", 62.5), ("Apr 2025", 62), ("Feb 2025", 62)], Self.bold13)
        add([("PM", 20), ("AM", 20)], Self.medium13)
        add(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"].map { ($0, 13.5) }, Self.bold10, height: 13, baseline: 10)
        add((1...31).map { ("\($0)", $0 < 10 ? 6.5 : 12.5) }, Self.regular11, height: 14, baseline: 11)
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view.environment(\.timeZone, Self.utc))
        runtime.layout(in: size)
        return runtime
    }

    @Observable final class Model: @unchecked Sendable { var date = DatePickerTests.fixed }

    private func field(_ r: Runtime) -> DateFieldNode { r.root.descendants(where: { $0 is DateFieldNode }).first as! DateFieldNode }
    private func parts(_ date: Date) -> _DateParts {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = Self.utc
        return _DateMath.parts(of: date, calendar: calendar)
    }

    @Test func fieldGeometry() {
        let r = runtime(VStack(alignment: .leading, spacing: 12) {
            DatePicker("Date", selection: .constant(Self.fixed), displayedComponents: .date)._probe("date")
            DatePicker("Date", selection: .constant(Self.fixed))._probe("dateTime")
            DatePicker("Date", selection: .constant(Self.fixed), displayedComponents: .hourAndMinute).labelsHidden()._probe("time")
            DatePicker("Date", selection: .constant(Self.fixed), displayedComponents: .date).datePickerStyle(.field)._probe("field")
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        // Label + 8 + [1 + bezel 72 + 9 + stepper 13]: 131.5 × 22; the date and time 137 + 23; time 57 + 23.
        let date = r.probeFrames["date"]!
        #expect(date.size == CGSize(width: 131.5, height: 22) && date.minY == 20)
        #expect(r.probeFrames["dateTime"]?.width == 28.5 + 8 + 160)
        #expect(r.probeFrames["time"]?.size == CGSize(width: 80, height: 22) && r.probeFrames["time"]?.minY == 88)
        // The field style: the bezel is the control with 3 pt insets, 21 tall.
        #expect(r.probeFrames["field"]?.size == CGSize(width: 28.5 + 8 + 78, height: 21))
        let node = field(r)
        #expect(node.bezel == CGRect(x: 2, y: 0, width: 70, height: 22))
        #expect(node.stepperRect == CGRect(x: 82.5, y: 1, width: 12.5, height: 20))
        #expect(node.slots.map(\.rect.minX) == [3, 23, 43])
        #expect(node.text == "3/15/2025")
        let painted = r.render(scale: 2).commands.map(\.description)
        // The month is right-aligned in its slot ("3" is 8 wide here), the year at its slot; the
        // bezel's border box is the 22 pt frame grown by a point.
        let control = date.minX + 28.5 + 8
        func fmt(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }
        #expect(painted.contains { $0.hasPrefix("drawText(\"3\"") && $0.contains(" at \(fmt(control + 3 + 16 - 8)),36 ") })
        #expect(painted.contains { $0.hasPrefix("drawText(\"2025\"") && $0.contains(" at \(fmt(control + 43)),36 ") })
        #expect(painted.contains { $0.hasPrefix("fillRRect(\(fmt(control + 1)), 19, 72, 24) r=6") })
    }

    @Test func steppingAndSelection() {
        let model = Model()
        let r = runtime(DatePicker("Date", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .date)
            .labelsHidden()._probe("picker").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        let node = field(r)
        // The stepper's upper half steps the first component (the month) when none is selected.
        r.pointerDown(at: CGPoint(x: 88, y: 5)); r.pointerUp(at: CGPoint(x: 88, y: 5))
        #expect(parts(model.date).month == 4 && parts(model.date).day == 15)
        // A press on the day slot selects it; Down steps it back; arrows move the selection.
        r.pointerDown(at: CGPoint(x: 30, y: 11)); r.pointerUp(at: CGPoint(x: 30, y: 11))
        #expect(node.selectedComponent == .day)
        #expect(r.keyDown(KeyEvent(key: .downArrow)) && parts(model.date).day == 14)
        #expect(r.keyDown(KeyEvent(key: .rightArrow)) && node.selectedComponent == .year)
        #expect(r.keyDown(KeyEvent(key: .upArrow)) && parts(model.date).year == 2026)
        // The focused field paints the selected slot in the accent colour.
        let painted = r.render(scale: 2).commands.map(\.description)
        #expect(painted.contains { $0.hasPrefix("fillRRect(43, 3, 32, 16) r=2") })
    }

    @Test func rangeAndPeriod() {
        let model = Model()
        let r = runtime(DatePicker("Date", selection: Binding(get: { model.date }, set: { model.date = $0 }), in: ...Self.fixed, displayedComponents: .hourAndMinute)
            .labelsHidden().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        let node = field(r)
        #expect(node.text == "3:09 PM")
        // Incrementing past the maximum clamps; the period steps twelve hours.
        node.step(1)
        #expect(model.date == Self.fixed)
        r.pointerDown(at: CGPoint(x: 50, y: 11)); r.pointerUp(at: CGPoint(x: 50, y: 11))
        #expect(node.selectedComponent == .era)
        node.step(-1)
        #expect(parts(model.date).hour == 3 && node.text == "3:09 AM")
    }

    @Test func calendar() {
        let model = Model()
        let r = runtime(DatePicker("Calendar", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .date)
            .datePickerStyle(.graphical)._probe("picker").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        #expect(r.probeFrames["picker"] == CGRect(x: 0, y: 0, width: 54.5 + 8 + 138.5, height: 148))
        let node = r.root.descendants(where: { $0 is CalendarNode }).first as! CalendarNode
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = Self.utc
        let grid = _DateMath.grid(year: 2025, month: 3, calendar: calendar)
        // March 2025 starts on a Saturday: the first row shows 23…28 February and the 1st.
        #expect(grid[0].map(\.day) == [23, 24, 25, 26, 27, 28, 1] && grid[0][6].inMonth && !grid[0][0].inMonth)
        #expect(grid[5].map(\.day) == [30, 31, 1, 2, 3, 4, 5])
        // The selected day (Saturday the 15th, row 2) is highlighted at its cell.
        #expect(node.cell(row: 2, column: 6) == CGRect(x: 0.5 + 4 + 6 * 18.5, y: 47 - 9 + 36, width: 18.5, height: 18))
        let painted = r.render(scale: 2).commands.map(\.description)
        #expect(painted.contains { $0.hasPrefix("fillRRect(178, 75, 18.5, 16) r=3") })
        #expect(painted.contains { $0.hasPrefix("drawText(\"Mar 2025\"") })
        // Pressing a day selects it (keeping the time); the next arrow pages the shown month.
        let cell = node.cell(row: 1, column: 1)
        r.pointerDown(at: CGPoint(x: 62.5 + cell.midX, y: cell.midY)); r.pointerUp(at: CGPoint(x: 62.5 + cell.midX, y: cell.midY))
        #expect(parts(model.date).day == 3 && parts(model.date).hour == 15)
        let next = node.controls.next
        r.pointerDown(at: CGPoint(x: 62.5 + next.midX, y: next.midY)); r.pointerUp(at: CGPoint(x: 62.5 + next.midX, y: next.midY))
        #expect(node.visibleMonth == (2025, 4))
        #expect(r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Apr 2025\"") })
    }

    @Test func clock() {
        let r = runtime(DatePicker("Clock", selection: .constant(Self.fixed), displayedComponents: .hourAndMinute)
            .datePickerStyle(.graphical)._probe("picker").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        #expect(r.probeFrames["picker"] == CGRect(x: 0, y: 0, width: 34.5 + 8 + 119, height: 119))
        let painted = r.render(scale: 2).commands.map(\.description)
        #expect(painted.filter { $0.hasPrefix("drawText") }.count == 1 + 12 + 1)   // label, numerals, "PM"
        #expect(painted.contains { $0.hasPrefix("drawText(\"PM\"") })
        #expect(painted.filter { $0.hasPrefix("strokeGradient") }.count == 2)
    }
}
#endif
