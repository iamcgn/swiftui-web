// Right-to-left layout (sw-rtl, Docs/elements/Layout.md): the containers are held to goldens in
// GoldenFrameTests (layout/rtl-*); here the controls (measured on a macOS 26.6 golden whose
// control sizes the clone does not model), hit testing through mirrored frames, the scroll
// view's input direction, text alignment and the shape and image behaviours.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct RTLTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private static var entries: [String: RecordedTextEngine.Entry] {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("One", 25.0), ("Three", 36.0), ("A", 9.0), ("B", 9.0)] {
            entries[RecordedTextEngine.key(font: system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
        }
        return entries
    }

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 300, height: 100)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: Self.entries)
        runtime.mount(view.environment(\.layoutDirection, .rightToLeft))
        runtime.layout(in: size)
        return runtime
    }

    private func commands(_ runtime: Runtime) -> [String] { runtime.render(scale: 2).commands.map(\.description) }

    private func ltrRuntime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: Self.entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 300, height: 100))
        return runtime
    }

    /// The numbers inside a command's first parentheses ("fillRRect(119, 38, 54, 24) …" → 119, 38, 54, 24).
    private func numbers(_ command: String) -> [Double] {
        let inner = command.split(separator: "(", maxSplits: 1)[1].split(separator: ")", maxSplits: 1)[0]
        return inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
    private func x(_ command: String) -> Double { numbers(command)[0] }
    private func width(_ command: String) -> Double { numbers(command)[2] }

    @Test func progressAndSliderFillFromTheTrailingEnd() {
        // The bar's 30 % sits at the right end of the 200 pt track.
        let bar = runtime(ProgressView(value: 0.3).frame(width: 200))
        #expect(commands(bar).last == "fillRRect(190, 46, 60, 8) r=4 #000000@\(85.0 / 255)")
        // The slider's knob mirrors its left-to-right position within the control, the filled
        // part runs from the knob to the right end.
        let slider = runtime(Slider(value: .constant(0.3)).frame(width: 200)._probe("slider"))
        let frame = slider.probeFrames["slider"]!
        let ltr = commands(ltrRuntime(Slider(value: .constant(0.3)).frame(width: 200)))
        let rtl = commands(slider)
        let ltrKnobCenter = x(ltr.last!) + width(ltr.last!) / 2
        let rtlKnobCenter = x(rtl.last!) + width(rtl.last!) / 2
        #expect(abs(rtlKnobCenter - (frame.minX + frame.maxX - ltrKnobCenter)) < 1e-9, "\(ltr.last!) vs \(rtl.last!)")
        #expect(abs(x(rtl[1]) - rtlKnobCenter) < 1e-9 && abs(x(rtl[1]) + width(rtl[1]) - frame.maxX) < 1e-9, "fill \(rtl[1])")
        // The value grows leftward: a press near the right end is near the minimum.
        var value = 0.3
        let interactive = runtime(Slider(value: Binding(get: { value }, set: { value = $0 })).frame(width: 200)._probe("slider"))
        let track = interactive.probeFrames["slider"]!
        interactive.pointerDown(at: CGPoint(x: track.maxX - 12, y: track.midY))
        interactive.pointerUp(at: CGPoint(x: track.maxX - 12, y: track.midY))
        #expect(value < 0.05, "\(value)")
        interactive.pointerDown(at: CGPoint(x: track.minX + 12, y: track.midY))
        interactive.pointerUp(at: CGPoint(x: track.minX + 12, y: track.midY))
        #expect(value > 0.95, "\(value)")
    }

    @Test func toggleMirrorsLabelAndKnob() {
        let r = runtime(Toggle("One", isOn: .constant(true)).toggleStyle(.switch)._probe("toggle"))
        let frame = r.probeFrames["toggle"]!
        let rtl = commands(r)
        let ltr = commands(ltrRuntime(Toggle("One", isOn: .constant(true)).toggleStyle(.switch)))
        // The switch is left of the label: the text is drawn at the right end of the toggle.
        let text = rtl.first { $0.hasPrefix("drawText") }!
        let textX = Double(text.split(separator: " at ")[1].split(separator: ",")[0])!
        #expect(textX > frame.midX, "\(text) in \(frame)")
        // On: the knob (the last rounded fill) sits at the left end of its track, the mirror of
        // the left-to-right knob within the control.
        let ltrKnob = ltr.last { $0.hasPrefix("fillRRect") }!, rtlKnob = rtl.last { $0.hasPrefix("fillRRect") }!
        let ltrCenter = x(ltrKnob) + width(ltrKnob) / 2, rtlCenter = x(rtlKnob) + width(rtlKnob) / 2
        #expect(abs(rtlCenter - (frame.minX + frame.maxX - ltrCenter)) < 1e-9, "\(ltrKnob) vs \(rtlKnob)")
    }

    @Test func pressesLandOnMirroredFrames() {
        var pressed: [String] = []
        let r = runtime(HStack(spacing: 10) {
            Button("A") { pressed.append("A") }.buttonStyle(.plain)._probe("a")
            Button("B") { pressed.append("B") }.buttonStyle(.plain)._probe("b")
        })
        let a = r.probeFrames["a"]!, b = r.probeFrames["b"]!
        #expect(a.minX > b.maxX)   // A is on the right
        r.pointerDown(at: CGPoint(x: a.midX, y: a.midY)); r.pointerUp(at: CGPoint(x: a.midX, y: a.midY))
        r.pointerDown(at: CGPoint(x: b.midX, y: b.midY)); r.pointerUp(at: CGPoint(x: b.midX, y: b.midY))
        #expect(pressed == ["A", "B"])
    }

    @Test func horizontalScrollStartsAtTheTrailingEndAndSwipesNaturally() {
        let r = runtime(ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(0..<6) { index in Color.red.frame(width: 50, height: 40)._probe("s\(index)") }
            }
        }.frame(width: 180, height: 60)._probe("scroll"), size: CGSize(width: 200, height: 80))
        let scroll = r.probeFrames["scroll"]!
        // The first element is at the right end, the last cut off to the left.
        #expect(r.probeFrames["s0"]!.maxX == scroll.maxX && r.probeFrames["s5"]!.minX == scroll.maxX - 300)
        // A leftward wheel (the way a reader of right-to-left text moves on) reveals the left end.
        r.scrollWheel(by: CGSize(width: -60, height: 0), at: CGPoint(x: scroll.midX, y: scroll.midY))
        r.layout(in: CGSize(width: 200, height: 80))
        #expect(r.probeFrames["s0"]!.maxX == scroll.maxX + 60)
        // Scrolling back past the start clamps at the trailing end.
        r.scrollWheel(by: CGSize(width: 200, height: 0), at: CGPoint(x: scroll.midX, y: scroll.midY))
        r.layout(in: CGSize(width: 200, height: 80))
        #expect(r.probeFrames["s0"]!.maxX == scroll.maxX)
    }

    @Test func textAlignmentFollowsTheDirection() {
        var environment = EnvironmentValues()
        #expect(environment._resolvedTextAlignment == 0)
        environment.layoutDirection = .rightToLeft
        #expect(environment._resolvedTextAlignment == 1)
        environment.multilineTextAlignment = .trailing
        #expect(environment._resolvedTextAlignment == 0)
        environment.multilineTextAlignment = .center
        #expect(environment._resolvedTextAlignment == 0.5)
    }

    @Test func shapesAndImagesFlipByTheirBehaviour() {
        #expect(LayoutDirectionBehavior.mirrors == .mirrors(in: .rightToLeft))
        #expect(LayoutDirectionBehavior.mirrors.flips(in: .rightToLeft) && !LayoutDirectionBehavior.mirrors.flips(in: .leftToRight))
        #expect(!LayoutDirectionBehavior.fixed.flips(in: .rightToLeft) && LayoutDirectionBehavior.mirrors(in: .leftToRight).flips(in: .leftToRight))
        #expect(Rectangle().layoutDirectionBehavior == .mirrors)
        // A triangle pointing right fills a path whose rightmost point becomes the leftmost.
        struct Arrow: Shape {
            func path(in rect: CGRect) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
                return path
            }
        }
        struct FixedArrow: Shape {
            func path(in rect: CGRect) -> Path { Arrow().path(in: rect) }
            var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
        }
        let mirrored = runtime(Arrow().fill(.red).frame(width: 40, height: 30)).render(scale: 2).commands
        let fixed = runtime(FixedArrow().fill(.red).frame(width: 40, height: 30)).render(scale: 2).commands
        var mirroredPoints: [CGFloat] = [], fixedPoints: [CGFloat] = []
        for case .fillPath(let path, _, _) in mirrored { for case .line(let p) in path.elements { mirroredPoints.append(p.x) } }
        for case .fillPath(let path, _, _) in fixed { for case .line(let p) in path.elements { fixedPoints.append(p.x) } }
        // The frame spans 130…170; the first line goes to the tip: at 130 mirrored, 170 fixed.
        #expect(mirroredPoints.first == 130 && fixedPoints.first == 170, "\(mirroredPoints) \(fixedPoints)")
        // An image is not flipped unless asked to.
        let plain = commands(runtime(Image(systemName: "arrow.right")))
        let flipped = commands(runtime(Image(systemName: "arrow.right").flipsForRightToLeftLayoutDirection(true)))
        #expect(!plain.contains { $0.hasPrefix("concat") } && flipped.contains { $0.hasPrefix("concat") && $0.contains("-1") })
    }

    @Test func leftToRightIslandAndEnvironmentReads() {
        // A nested left-to-right environment lays its own children out as written.
        let r = runtime(HStack(spacing: 0) {
            Color.red.frame(width: 30, height: 20)._probe("a")
            HStack(spacing: 0) {
                Color.blue.frame(width: 30, height: 20)._probe("b")
                Color.green.frame(width: 30, height: 20)._probe("c")
            }
            .environment(\.layoutDirection, .leftToRight)
        })
        let a = r.probeFrames["a"]!, b = r.probeFrames["b"]!, c = r.probeFrames["c"]!
        #expect(a.minX > b.minX && b.maxX == c.minX)
    }
}
#endif
