// Canvas (Phase 2): the renderer's fills, strokes, text, transforms, opacity and clips reach the
// display list in the canvas's coordinate space, clipped to its bounds.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct CanvasTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func render<V: View>(_ view: V) -> [String] {
        let runtime = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: "Hi")] = .init(width: 14, height: 16, firstBaseline: 13, lastBaseline: 13)
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime.render(scale: 2).commands.map(\.description)
    }

    @Test func drawsInCanvasSpaceClippedToBounds() {
        let commands = render(Canvas { context, size in
            context.fill(Path(CGRect(x: 10, y: 10, width: 20, height: 20)), with: .color(.red))
            context.stroke(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)), with: .color(.blue), lineWidth: 2)
            context.draw(Text("Hi"), at: CGPoint(x: 50, y: 50), anchor: .center)
        }.frame(width: 100, height: 60))
        // The canvas is centred at (50, 20); its drawing is clipped to its bounds and offset.
        #expect(commands.first == "save")
        #expect(commands.contains("clipRect(50, 20, 100, 60)"))
        #expect(commands.contains { $0.hasPrefix("fillPath(5 elements) #FF383C") })
        #expect(commands.contains { $0.hasPrefix("strokePath(5 elements) w=2") && $0.contains("#0088FF") })
        // "Hi" (14 × 16) centred at (50, 50) → origin (43, 42) → baseline 55, in canvas space +(50, 20).
        #expect(commands.contains("drawText(\"Hi\" system 13 w400 at 93,75 #000000@0.85)"))
        #expect(commands.last == "restore")
    }

    @Test func transformsOpacityAndClipsApply() {
        let commands = render(Canvas { context, _ in
            var moved = context
            moved.translateBy(x: 10, y: 5)
            moved.scaleBy(x: 2, y: 2)
            moved.fill(Path(CGRect(x: 0, y: 0, width: 5, height: 5)), with: .color(.red))
            var faded = context
            faded.opacity = 0.5
            faded.clip(to: Path(CGRect(x: 0, y: 0, width: 10, height: 10)))
            faded.fill(Path(CGRect(x: 0, y: 0, width: 40, height: 40)), with: .color(.blue))
            var rotated = context
            rotated.rotate(by: .degrees(90))
            rotated.draw(Text("Hi"), at: .zero)
        }.frame(width: 100, height: 100))
        // The scaled square is 10 × 10 at (10, 5) in canvas space: its path's second point is (60, 55) absolute.
        let runtime = Runtime()
        runtime.mount(Canvas { context, _ in
            var moved = context
            moved.translateBy(x: 10, y: 5)
            moved.scaleBy(x: 2, y: 2)
            moved.fill(Path(CGRect(x: 0, y: 0, width: 5, height: 5)), with: .color(.red))
        }.frame(width: 100, height: 100))
        runtime.layout(in: CGSize(width: 200, height: 100))
        if case .fillPath(let path, _, _) = runtime.render(scale: 2).commands[2] {
            #expect(path.boundingRect == CGRect(x: 60, y: 5, width: 10, height: 10))
        } else {
            Issue.record("expected the scaled fill")
        }
        #expect(commands.contains("beginGroup(opacity: 0.5)"))
        #expect(commands.contains { $0.hasPrefix("clipPath(5 elements)") })
        // Rotated text goes through a transform op around the draw.
        #expect(commands.contains { $0.hasPrefix("concat(") })
    }

    @Test func canvasIsFlexible() {
        let runtime = Runtime()
        runtime.mount(VStack(spacing: 0) {
            Canvas { _, _ in }._probe("canvas")
            Color.red.frame(height: 20)
        })
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["canvas"] == CGRect(x: 0, y: 0, width: 200, height: 80))
    }
}
#endif
