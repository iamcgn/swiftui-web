// Toggle and Label (Phase 2): activation through the binding, disabled state, accessibility
// nodes, the checkbox and switch geometry and the icon alignment guide. Layout against goldens
// is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ToggleTests {
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func engine() -> RecordedTextEngine {
        RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.body, width: nil, string: "Enabled"): .init(width: 49, height: 18.5, firstBaseline: 14, lastBaseline: 14),
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Enabled"): .init(width: 49, height: 16, firstBaseline: 13, lastBaseline: 13),
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Title"): .init(width: 26.5, height: 16, firstBaseline: 13, lastBaseline: 13),
        ])
    }

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    @Test func checkboxGeometry() {
        // 16 pt box, 5 pt gap, .body label (18.5 tall); the box centres on the cap height:
        // baseline 14 − 9.16 / 2 − 8 = 1.42 from the top, pixel-rounded to 1.5 at 2×.
        let r = runtime(Toggle("Enabled", isOn: .constant(true))._probe("toggle"))
        #expect(r.probeFrames["toggle"] == CGRect(x: 65, y: 40.75, width: 70, height: 18.5))
        let commands = r.render(scale: 2).commands
        guard commands.count == 3, case .fillPath(let box, let fill, _) = commands[0], case .strokePath(let mark, let style, _) = commands[1],
              case .drawText(let text, _, let origin, _) = commands[2] else { Issue.record("unexpected \(commands)"); return }
        #expect(box.boundingRect == CGRect(x: 65, y: 42, width: 16, height: 16))   // 40.75 + 1.42 rounds to 42 at 2×
        #expect(abs(fill.alpha - 36.0 / 255) < 1e-9)
        #expect(style.lineWidth == 2 && style.lineCap == .round)
        #expect(mark.boundingRect.minX > 68 && mark.boundingRect.maxX < 78)
        #expect(text == "Enabled" && origin == CGPoint(x: 86, y: 55))
        // Off: no check mark; hidden label: the box alone.
        #expect(runtime(Toggle("Enabled", isOn: .constant(false))).render(scale: 2).commands.count == 2)
        let hidden = runtime(Toggle("Enabled", isOn: .constant(true)).labelsHidden()._probe("hidden"))
        #expect(hidden.probeFrames["hidden"] == CGRect(x: 92, y: 42, width: 16, height: 16))
    }

    @Test func switchAndButtonGeometry() {
        let sw = runtime(Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch)._probe("switch"))
        #expect(sw.probeFrames["switch"] == CGRect(x: 44.5, y: 38, width: 111, height: 24))
        let commands = sw.render(scale: 2).commands
        guard case .fillRRect(let track, _, _) = commands[1], case .fillRRect(let knob, _, let knobColor) = commands[2] else { Issue.record("unexpected \(commands)"); return }
        #expect(track == CGRect(x: 101.5, y: 38, width: 54, height: 24))
        #expect(knob == CGRect(x: 121.5, y: 40, width: 32, height: 20) && knobColor == .white)
        let off = runtime(Toggle("Enabled", isOn: .constant(false)).toggleStyle(.switch).labelsHidden()).render(scale: 2).commands
        guard case .fillRRect(let offKnob, _, _) = off[1] else { Issue.record("unexpected \(off)"); return }
        #expect(offKnob == CGRect(x: 75, y: 40, width: 32, height: 20))
        let button = runtime(Toggle("Enabled", isOn: .constant(true)).toggleStyle(.button)._probe("button"))
        #expect(button.probeFrames["button"] == CGRect(x: 63.5, y: 38, width: 73, height: 24))
        #expect(button.render(scale: 2).commands.map(\.description).first == "fillRRect(63.5, 38, 73, 24) r=6 #0088FF")
    }

    @Test func pressFlipsTheBindingUnlessDisabled() {
        let box = _Box(false)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let r = runtime(Toggle("Enabled", isOn: binding))
        r.pointerDown(at: CGPoint(x: 120, y: 50))
        r.pointerUp(at: CGPoint(x: 120, y: 50))
        #expect(box.value == true)
        // Released outside: no change.
        r.pointerDown(at: CGPoint(x: 120, y: 50))
        r.pointerUp(at: CGPoint(x: 10, y: 10))
        #expect(box.value == true)
        let disabled = runtime(Toggle("Enabled", isOn: binding).disabled(true))
        disabled.pointerDown(at: CGPoint(x: 120, y: 50))
        disabled.pointerUp(at: CGPoint(x: 120, y: 50))
        #expect(box.value == true)
        // Accessibility: a checkbox with its label and state; activation through the overlay.
        let tree = r.semanticsTree()
        #expect(tree.count == 1 && tree[0].role == .checkbox && tree[0].label == "Enabled" && tree[0].isOn == true)
        r.activate(semanticsIdentifier: tree[0].identifier)
        #expect(box.value == false)
    }

    @Test func labelAlignsIconOnTheCapHeight() {
        // A 12 pt icon centres 4.58 above the title's baseline: 13 − 4.58 − 6 = 2.42 from the top.
        let r = runtime(Label(title: { Text("Title")._probe("title") }, icon: { Color.red.frame(width: 12, height: 12)._probe("icon") })._probe("label"))
        let label = try! #require(r.probeFrames["label"]), icon = try! #require(r.probeFrames["icon"]), title = try! #require(r.probeFrames["title"])
        #expect(label.size == CGSize(width: 46.5, height: 16))
        #expect(abs(icon.minY - (label.minY + 2.42)) < 0.01 && icon.minX == label.minX)
        #expect(title.minX == label.minX + 20 && title.minY == label.minY)
        // A taller icon sets the height; the title's guide still lands on the icon's centre.
        let tall = runtime(Label(title: { Text("Title")._probe("title") }, icon: { Color.red.frame(width: 40, height: 40)._probe("icon") })._probe("label"))
        let tallLabel = try! #require(tall.probeFrames["label"]), tallTitle = try! #require(tall.probeFrames["title"])
        #expect(tallLabel.size == CGSize(width: 74.5, height: 40))
        #expect(abs(tallTitle.minY - (tallLabel.minY + 20 + 4.58 - 13)) < 0.01)
        #expect(runtime(Label("Title", image: "missing").labelStyle(.titleOnly)._probe("t")).probeFrames["t"]?.size == CGSize(width: 26.5, height: 16))
    }
}

private final class _Box: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
#endif
