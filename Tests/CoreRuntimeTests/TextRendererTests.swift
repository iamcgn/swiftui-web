// Text renderers and app text field styles, as Harbour's highlighted search matches and rounded
// setup fields use them: a renderer reads its runs' custom attributes, fills behind the marked
// ones and draws every run as the text would have; a text field style's body dresses the field
// it is handed, which draws with the style the body sets.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
private struct Highlight: TextAttribute {}

private struct HighlightRenderer: TextRenderer {
    var fill: Color
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flatMap(\.self) {
            if run[Highlight.self] != nil {
                context.fill(Rectangle().path(in: run.typographicBounds.rect), with: .style(fill))
            }
            context.draw(run)
        }
    }
}

/// Draws each line moved right, to check the context's transform reaches the runs.
private struct ShiftingRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var shifted = context
        shifted.translateBy(x: 10, y: 0)
        for line in layout { shifted.draw(line) }
    }
}

private struct RoundedFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 1, green: 0, blue: 0)))
    }
}

@Suite @MainActor struct TextRendererTests {
    private func commands<V: View>(_ view: V) -> [String] {
        let renderer = HeadlessRenderer(size: CGSize(width: 300, height: 100), textEngine: MonospaceTextEngine())
        renderer.mount(view)
        return renderer.renderFrame().commands.map(\.description)
    }

    @Test func aRendererFillsBehindMarkedRunsAndDrawsThemAll() {
        let text = Text("plain ") + Text("match").customAttribute(Highlight()) + Text(" tail")
        let painted = commands(text.textRenderer(HighlightRenderer(fill: Color(red: 1, green: 0, blue: 0))))
        let fills = painted.filter { $0.hasPrefix("fillPath(") && $0.contains("#FF0000") }
        #expect(fills.count == 1, "\(painted)")
        #expect(painted.contains { $0.hasPrefix("drawText(\"plain") } && painted.contains { $0.hasPrefix("drawText(\"match") }
            && painted.contains { $0.hasPrefix("drawText(\" tail") }, "\(painted)")
        // The fill comes before the run it marks.
        let fill = painted.firstIndex { $0.hasPrefix("fillPath(") } ?? .max
        let match = painted.firstIndex { $0.hasPrefix("drawText(\"match") } ?? -1
        #expect(fill < match)
        // Without a renderer, the same text draws the same runs and no fill.
        let plain = commands(text)
        #expect(!plain.contains { $0.hasPrefix("fillPath(") })
        #expect(plain.filter { $0.hasPrefix("drawText(") } == painted.filter { $0.hasPrefix("drawText(") })
    }

    @Test func aRunCarriesItsTextsAttributesAndBounds() {
        @MainActor final class Seen { var marked: [Bool] = []; var widths: [CGFloat] = []; var lines = 0 }
        let seen = Seen()
        struct Recording: TextRenderer {
            let seen: Seen
            func draw(layout: Text.Layout, in context: inout GraphicsContext) {
                seen.lines = layout.count
                for line in layout {
                    for run in line {
                        seen.marked.append(run[Highlight.self] != nil)
                        seen.widths.append(run.typographicBounds.width)
                        #expect(run.typographicBounds.rect.height > 0)
                    }
                }
            }
        }
        _ = commands((Text("ab") + Text("cd").customAttribute(Highlight())).textRenderer(Recording(seen: seen)))
        #expect(seen.lines == 1 && seen.marked == [false, true] && seen.widths.allSatisfy { $0 > 0 }, "\(seen.marked) \(seen.widths)")
    }

    @Test func theContextsTransformMovesTheRuns() {
        let moved = commands(Text("abc").textRenderer(ShiftingRenderer()))
        #expect(moved.contains { $0.hasPrefix("concat(1, 0, 0, 1, 10, 0)") }, "\(moved)")
        #expect(moved.contains { $0.hasPrefix("drawText(\"abc") })
    }

    @Test func aTextFieldStylesBodyDressesThePlainField() {
        let styled = commands(TextField("Token", text: .constant("")).textFieldStyle(RoundedFieldStyle()))
        // The style's red background, and the field inside it plain: no rounded bezel stroke.
        #expect(styled.contains { ($0.hasPrefix("fillPath(") || $0.hasPrefix("fillRRect(")) && $0.contains("#FF0000") }, "\(styled)")
        #expect(!styled.contains { $0.hasPrefix("strokePath(") }, "\(styled)")
        let runtime = Runtime()
        runtime.textEngine = MonospaceTextEngine()
        runtime.mount(SecureField("Secret", text: .constant("x")).textFieldStyle(RoundedFieldStyle()))
        runtime.layout(in: CGSize(width: 300, height: 100))
        let field = runtime.semanticsTree().first { $0.role == .textField }
        #expect(field?.label == "Secret" && field?.textInput?.isSecure == true)
    }
}
#endif
