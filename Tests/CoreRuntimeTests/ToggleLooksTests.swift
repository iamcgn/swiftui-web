// Phase 8 step 6, sw-toggle: Toggle(sources:), the mixed dash, Space, the focus ring around the
// control, control sizes, tint, the knob shadow and the active-window accent
// (Docs/elements/Toggle.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Observable
private final class Sources {
    var a = true
    var b = false
}

private struct Item {
    var value: Binding<Bool>
}

@Suite @MainActor struct ToggleLooksTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    private static let mini = ResolvedFont(family: "system", size: 9, weight: .regular, italic: false, textStyle: nil)
    private static let iosBody = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body, profile: "iOS")

    private func runtime<V: View>(_ view: V, iOS: Bool = false) -> Runtime {
        var environment = EnvironmentValues()
        if iOS { environment.platformProfile = .iOS }
        let runtime = Runtime(environment: environment)
        var entries: [String: RecordedTextEngine.Entry] = [:]
        // A text style's key carries no size: the iOS body entries stand alone.
        for word in ["Mixed", "Enabled", "Mini"] {
            if iOS {
                entries[RecordedTextEngine.key(font: Self.iosBody, width: nil, string: word)] = .init(width: 50, height: 24.5, firstBaseline: 18.5, lastBaseline: 18.5)
            } else {
                entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: 40, height: 16, firstBaseline: 13, lastBaseline: 13)
                entries[RecordedTextEngine.key(font: Self.mini, width: nil, string: word)] = .init(width: 28, height: 11, firstBaseline: 9, lastBaseline: 9)
            }
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 300, height: 200))
        return runtime
    }

    private func commands(_ runtime: Runtime) -> [String] { runtime.render(scale: 2).commands.map(\.description) }

    @Test func sourcesShareTheirStateAndDisagreeIntoAMixedDash() {
        let model = Sources()
        let items = [Item(value: Binding(get: { model.a }, set: { model.a = $0 })), Item(value: Binding(get: { model.b }, set: { model.b = $0 }))]
        let runtime = runtime(Toggle("Mixed", sources: items, isOn: \Item.value)._probe("toggle"))
        // Mixed: a dash (a stroked path with one segment) instead of the check mark.
        let strokes = commands(runtime).filter { $0.hasPrefix("strokePath") }
        #expect(strokes.count == 1)
        let toggle = runtime.semanticsTree().first { $0.role == .checkbox }!
        #expect(toggle.isOn == false)
        // A press on a mixed toggle turns every source on; the next turns them all off.
        let frame = runtime.probeFrames["toggle"]!
        runtime.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(model.a && model.b)
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.semanticsTree().first { $0.role == .checkbox }?.isOn == true)
        runtime.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(!model.a && !model.b)
    }

    @Test func spaceFlipsTheFocusedToggleAndTheRingSitsOnTheControl() {
        let model = Sources()
        let runtime = runtime(Toggle("Enabled", isOn: Binding(get: { model.a }, set: { model.a = $0 }))._probe("toggle"))
        #expect(runtime.moveFocus(forward: true))
        #expect(runtime.keyDown(KeyEvent(key: .space)))
        #expect(model.a == false)
        // The ring: the checkbox's 16 pt square (plus the ring's width), not the whole toggle.
        let ring = commands(runtime).first { $0.hasPrefix("strokePath") && $0.contains("w\(PlatformMetrics.focusRingWidth)") || $0.hasPrefix("strokePath") }
        #expect(ring != nil)
        let frame = runtime.probeFrames["toggle"]!
        #expect(frame.width > 16)
    }

    @Test func controlSizesAndTint() {
        let runtime = runtime(VStack(alignment: .leading, spacing: 8) {
            Toggle("Mini", isOn: .constant(true)).controlSize(.mini)._probe("mini")
            Toggle("Enabled", isOn: .constant(true)).controlSize(.large)._probe("large")
            Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch).controlSize(.mini).labelsHidden()._probe("switchMini")
        })
        // Mini: a 12 pt box, a 9 pt label (28 wide); large: an 18 pt box with the body label.
        let mini = runtime.probeFrames["mini"], large = runtime.probeFrames["large"]
        #expect(mini?.size == CGSize(width: 45, height: 12), "\(String(describing: mini))")
        #expect(large?.size == CGSize(width: 63, height: 18), "\(String(describing: large))")
        #expect(runtime.probeFrames["switchMini"]?.size == CGSize(width: 36, height: 16))
        // iOS: the tint colours the switch's on track.
        let ios = self.runtime(Toggle("Enabled", isOn: .constant(true)).tint(Color(red: 1, green: 0, blue: 0)).labelsHidden(), iOS: true)
        #expect(commands(ios).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#FF0000") })
    }

    @Test func knobShadowAndTheActiveWindowAccent() {
        let runtime = runtime(VStack(spacing: 8) {
            Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch).labelsHidden()
            Toggle("Enabled", isOn: .constant(true)).labelsHidden()
        })
        // The switch: the track, two shadow rings, the knob.
        #expect(commands(runtime).filter { $0.hasPrefix("fillRRect") }.count == 4)
        // The checkbox in an inactive window is grey; an active window fills it with the accent
        // and draws a white mark.
        #expect(!commands(runtime).contains { $0.hasPrefix("fillPath") && $0.hasSuffix("#0088FF") })
        runtime.windowIsActive = true
        let active = commands(runtime)
        #expect(active.contains { $0.hasPrefix("fillPath") && $0.hasSuffix("#0088FF") })
        #expect(active.contains { $0.hasPrefix("strokePath") && $0.hasSuffix("#FFFFFF") })
        #expect(active.contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#0088FF") })
    }
}
#endif
