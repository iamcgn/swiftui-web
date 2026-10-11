// ColorPicker: the well's size and label row, the painted well (grey ground, swatch over the
// black/white diagonal, inner stroke), translucent colours, hidden labels, the disabled look,
// the well's semantics, and the preset panel a press opens (choosing a swatch, the opacity
// slider). Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ColorPickerTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Accent", 42.5), ("Tint", 23.5), ("Opacity", 46.0), ("Above", 38.5)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func relayout(_ r: Runtime, height: CGFloat = 200) { r.layout(in: CGSize(width: 320, height: height)) }
    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
    private func press(_ r: Runtime, _ point: CGPoint) { r.pointerDown(at: point); r.pointerUp(at: point) }

    @Test func layoutAndPainting() {
        let r = runtime(VStack(alignment: .leading, spacing: 12) {
            ColorPicker("Accent", selection: .constant(.red))._probe("red")
            ColorPicker("Accent", selection: .constant(.red)).labelsHidden()._probe("hidden")
            ColorPicker("Tint", selection: .constant(.blue), supportsOpacity: false)._probe("opaque")
            ColorPicker("Accent", selection: .constant(.red)).disabled(true)._probe("disabled")
        })
        // Label, 8 pt, the 48 × 24 well; the body label centred at fractional points.
        #expect(r.probeFrames["red"]?.size == CGSize(width: 98.5, height: 24))
        #expect(r.probeFrames["hidden"]?.size == CGSize(width: 48, height: 24))
        #expect(r.probeFrames["opaque"]?.size == CGSize(width: 79.5, height: 24))
        let painted = commands(r)
        // The grey ground (25/255 black), the white and black halves of the swatch, the colour
        // (#FF383C), the inner stroke; the disabled well paints everything at half opacity.
        #expect(painted.filter { $0.hasPrefix("fillPath") && $0.contains("#000000@0.098") }.count == 3)
        #expect(painted.filter { $0.hasPrefix("fillPath") && $0.contains("#000000@0.049") }.count == 1)
        #expect(painted.filter { $0.hasPrefix("fillPath") && $0.hasSuffix("#FF383C") }.count == 2)
        #expect(painted.filter { $0.hasPrefix("fillPath") && $0.contains("#FF383C@0.5") }.count == 1)
        #expect(painted.filter { $0.hasPrefix("fillPath") && $0.hasSuffix("#0088FF") }.count == 1)
        #expect(painted.filter { $0.hasPrefix("strokePath") && $0.hasSuffix("#000000@0.1") }.count == 3)
        // Translucent colours keep their alpha over the diagonal ground.
        let t = runtime(ColorPicker("Accent", selection: .constant(Color(red: 0.2, green: 0.6, blue: 0.4, opacity: 0.5))))
        #expect(commands(t).contains { $0.hasPrefix("fillPath") && $0.contains("#339966@0.5") })
    }

    @Test func formRowsAndBaseline() {
        let r = runtime(Form {
            ColorPicker("Accent", selection: .constant(.red))._probe("accent")
            ColorPicker("Tint", selection: .constant(.blue))._probe("tint")
            Toggle("Above", isOn: .constant(true))._probe("toggle")
        })
        // In a form the label sits on the well's baseline (1.5 pt above its bottom): 27 pt rows,
        // 8.15 apart, a checkbox row 8.15 below too (macOS 27; 26.2 put it 6 below).
        let accent = r.probeFrames["accent"]!, tint = r.probeFrames["tint"]!, toggle = r.probeFrames["toggle"]!
        #expect(accent.height == 27 && tint.height == 27)
        #expect(abs(tint.minY - accent.maxY - 8.15) < 0.01)
        #expect(abs(toggle.minY - tint.maxY - 8.15) < 0.01)
        // Labels share the form's label column (right-aligned).
        #expect(tint.minX == accent.minX + 42.5 - 23.5)
    }

    @Test func semanticsAndPanel() {
        let box = _ColorBox()
        // A tall window so the panel fits below the well.
        let r = runtime(ColorPicker("Accent", selection: Binding(get: { box.color }, set: { box.color = $0 }))._probe("picker"), size: CGSize(width: 320, height: 500))
        let well = r.semanticsTree().first { $0.role == .button }!
        #expect(well.label == "Accent, color" && well.value == "Red")
        #expect(well.frame.size == CGSize(width: 48, height: 24))
        // A press opens the preset panel below the well: 16 swatches and the opacity slider.
        press(r, CGPoint(x: well.frame.midX, y: well.frame.midY))
        relayout(r, height: 500)
        #expect(r.hasPresentations)
        let swatches = r.semanticsTree().filter { $0.role == .button && $0.label != "Accent, color" }
        #expect(swatches.count == 16 && swatches.first?.label == "Red" && swatches.last?.label == "Clear")
        #expect(swatches.allSatisfy { $0.frame.minY > well.frame.maxY })
        #expect(r.semanticsTree().contains { $0.role == .slider })
        // Choosing a swatch sets the colour and closes the panel.
        let blue = swatches.first { $0.label == "Blue" }!
        press(r, CGPoint(x: blue.frame.midX, y: blue.frame.midY))
        #expect(box.color == .blue)
        relayout(r, height: 500)
        #expect(!r.hasPresentations)
        #expect(r.semanticsTree().first { $0.role == .button }?.value == "Blue")
        // Without opacity support the panel has no slider; a disabled well does not open.
        let opaque = runtime(ColorPicker("Tint", selection: .constant(.blue), supportsOpacity: false))
        let opaqueWell = opaque.semanticsTree().first { $0.role == .button }!
        press(opaque, CGPoint(x: opaqueWell.frame.midX, y: opaqueWell.frame.midY))
        relayout(opaque)
        #expect(opaque.hasPresentations && !opaque.semanticsTree().contains { $0.role == .slider })
        let disabled = runtime(ColorPicker("Tint", selection: .constant(.blue)).disabled(true))
        let disabledWell = disabled.semanticsTree().first { $0.role == .button }!
        press(disabled, CGPoint(x: disabledWell.frame.midX, y: disabledWell.frame.midY))
        #expect(!disabled.hasPresentations)
    }

    /// sw-colorpicker: a host with a system colour chooser takes the press (no popover), the
    /// well's frame turns the focus blue while the chooser targets it, picks flow into the
    /// binding (the alpha kept to the well's when the chooser has none), closing restores the
    /// grey; Space on the focused well asks too; `CGColor` bindings and dropped colours.
    @Test func hostPanelKeyboardAndDrops() {
        let box = _ColorBox()
        let r = runtime(ColorPicker("Accent", selection: Binding(get: { box.color }, set: { box.color = $0 }))._probe("picker"), size: CGSize(width: 320, height: 200))
        var requests: [ColorPanelRequest] = []
        r.colorPanelHandler = { requests.append($0); return true }
        let well = r.semanticsTree().first { $0.role == .button }!
        press(r, CGPoint(x: well.frame.midX, y: well.frame.midY))
        #expect(requests.count == 1 && requests[0].identifier == well.identifier && requests[0].supportsOpacity && requests[0].anchor == well.frame)
        #expect(requests[0].color == RGBA(r: 255, g: 56, b: 60, a: 1))
        #expect(!r.hasPresentations)
        // The active frame: the 3 pt ring is the focus blue (71, 145, 248) instead of 25/255 black.
        func frameFill() -> String? { commands(r).first { $0.hasPrefix("fillPath") } }
        #expect(frameFill()?.contains("#4791F8") == true, "\(frameFill() as Any)")
        r.colorPanel(well.identifier, didPick: RGBA(red: 0, green: 0.5, blue: 1, alpha: 0.5))
        #expect(box.color == Color(red: 0, green: 0.5, blue: 1, opacity: 0.5))
        r.colorPanelDidClose(well.identifier)
        #expect(frameFill()?.contains("#000000@0.098") == true, "\(frameFill() as Any)")
        // Space on the focused well asks the host again.
        r.focus(semanticsIdentifier: well.identifier)
        _ = r.keyDown(KeyEvent(key: .space))
        #expect(requests.count == 2)
        // Without opacity support a pick keeps alpha 1.
        let opaqueBox = _ColorBox()
        let opaque = runtime(ColorPicker("Tint", selection: Binding(get: { opaqueBox.color }, set: { opaqueBox.color = $0 }), supportsOpacity: false))
        opaque.colorPanelHandler = { _ in true }
        let opaqueWell = opaque.semanticsTree().first { $0.role == .button }!
        press(opaque, CGPoint(x: opaqueWell.frame.midX, y: opaqueWell.frame.midY))
        opaque.colorPanel(opaqueWell.identifier, didPick: RGBA(red: 0, green: 0.5, blue: 1, alpha: 0.5))
        #expect(opaqueBox.color == Color(red: 0, green: 0.5, blue: 1))
        // A CGColor binding reads and writes through the picker.
        let cgBox = _CGColorBox()
        let cg = runtime(ColorPicker("Accent", selection: Binding(get: { cgBox.color }, set: { cgBox.color = $0 })))
        #expect(cg.semanticsTree().first { $0.role == .button }?.value == "Color")
        cg.colorPanelHandler = { _ in true }
        let cgWell = cg.semanticsTree().first { $0.role == .button }!
        press(cg, CGPoint(x: cgWell.frame.midX, y: cgWell.frame.midY))
        cg.colorPanel(cgWell.identifier, didPick: RGBA(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(RGBA(cgColor: cgBox.color) == RGBA(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(Color(cgColor: cgBox.color).cgColor.flatMap(RGBA.init(cgColor:)) == RGBA(red: 1, green: 0, blue: 0, alpha: 1) && Color.red.cgColor == nil)
        // A dragged colour dropped on the well becomes its selection (the well highlights while targeted).
        let dropBox = _ColorBox()
        let d = runtime(HStack(spacing: 40) {
            Color.green.frame(width: 40, height: 40).draggable(Color.green)._probe("source")
            ColorPicker("Accent", selection: Binding(get: { dropBox.color }, set: { dropBox.color = $0 }))._probe("picker")
        }, size: CGSize(width: 320, height: 200))
        let source = d.probeFrames["source"]!, target = d.semanticsTree().first { $0.role == .button }!.frame
        d.pointerDown(at: CGPoint(x: source.midX, y: source.midY))
        d.pointerMoved(to: CGPoint(x: source.midX + 10, y: source.midY))
        d.pointerMoved(to: CGPoint(x: target.midX, y: target.midY))
        #expect(d.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("fillPath") && $0.contains("#4791F8") })
        d.pointerUp(at: CGPoint(x: target.midX, y: target.midY))
        #expect(dropBox.color == .green)
    }
}

@MainActor final class _CGColorBox { var color: CGColor = RGBA(red: 0, green: 0, blue: 1, alpha: 1).cgColor }

@Observable @MainActor final class _ColorBox { var color: Color = .red }
#endif
