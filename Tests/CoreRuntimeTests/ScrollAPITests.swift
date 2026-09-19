// Phase 8 step 6, sw-scroll-apis: scroll position, targets, geometry and phases
// (Docs/elements/ScrollView.md). The measured behaviours are in the scroll/position,
// scroll/margins, scroll/geometry and scroll/anchor-roles goldens; these cover the gestures.
import Testing
import SwiftUI

@Observable
private final class PositionModel {
    var id: Int? = 10
    var position = ScrollPosition()
    var log: [String] = []
    var flash = 0
}

private struct Rows: View {
    var count = 30
    var height: CGFloat = 20
    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            Color.blue.frame(width: 100, height: height)._probe("row\(index)")
        }
    }
}

private struct Positioned: View {
    let model: PositionModel
    var body: some View {
        ScrollView {
            VStack(spacing: 0) { Rows() }.scrollTargetLayout()
        }
        .scrollPosition(id: Binding(get: { model.id }, set: { model.id = $0 }))
        ._probe("scroll")
    }
}

private struct PositionedByValue: View {
    let model: PositionModel
    var body: some View {
        ScrollView {
            VStack(spacing: 0) { Rows() }.scrollTargetLayout()
        }
        .scrollPosition(Binding(get: { model.position }, set: { model.position = $0 }))
    }
}

private struct Pages: View {
    var behavior: any ScrollTargetBehavior = .paging
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in Color.blue.frame(width: 300, height: 200)._probe("p\(index)") }
            }
            .scrollTargetLayout()
        }
        .modifier(_AnyBehavior(behavior: behavior))
        .frame(width: 300, height: 200)
    }
}

private struct _AnyBehavior: ViewModifier {
    let behavior: any ScrollTargetBehavior
    func body(content: Content) -> some View {
        content.environment(\._scrollTargetBehavior, behavior)
    }
}

private struct Phased: View {
    let model: PositionModel
    var body: some View {
        ScrollView { VStack(spacing: 0) { Rows(count: 50) } }
            .onScrollPhaseChange { old, new in model.log.append("\(old)→\(new)") }
    }
}

private struct Geometry: View {
    let model: PositionModel
    var body: some View {
        ScrollView { VStack(spacing: 0) { Rows() } }
            .contentMargins(.top, 20, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in model.log.append("\(new)") }
    }
}

private struct Flashing: View {
    let model: PositionModel
    var body: some View {
        ScrollView { VStack(spacing: 0) { Rows() } }
            .scrollIndicatorsFlash(trigger: model.flash)
            .frame(width: 100, height: 200)
    }
}

@Suite @MainActor struct ScrollAPITests {
    private let size = CGSize(width: 300, height: 200)

    private func settled(_ runtime: Runtime) {
        var frames = 0
        while runtime.advanceScrollAnimations(elapsed: 0.016) { frames += 1; #expect(frames < 1000) }
        runtime.layout(in: size)
    }

    @Test func positionBindingFollowsTheUserAndScrollsOnWrites() {
        let model = PositionModel()
        let runtime = Runtime()
        runtime.mount(Positioned(model: model))
        runtime.layout(in: size)
        // The initial value does not scroll (scroll/position).
        #expect(runtime.probeFrames["row0"]?.minY == 0)
        // A wheel scroll positions the row showing the most; rows 3–11 are whole, row 2 is cut.
        runtime.scrollWheel(by: CGSize(width: 0, height: 45), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        #expect(model.id == 3)
        // Writing the binding scrolls with the smallest change: row 20 ends up bottom-aligned.
        model.id = 20
        runtime.layout(in: size)
        #expect(runtime.probeFrames["row20"]?.minY == 180)
        // A programmatic scroll leaves the binding alone; the next user scroll updates it.
        #expect(model.id == 20)
        runtime.scrollWheel(by: CGSize(width: 0, height: 20), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        #expect(model.id == 12)
    }

    @Test func scrollPositionValueScrollsToEdgesAndPoints() {
        let model = PositionModel()
        let runtime = Runtime()
        runtime.mount(PositionedByValue(model: model))
        runtime.layout(in: size)
        model.position.scrollTo(edge: .bottom)
        runtime.layout(in: size)
        #expect(runtime.probeFrames["row29"]?.minY == 180)
        model.position.scrollTo(y: 40)
        runtime.layout(in: size)
        #expect(runtime.probeFrames["row0"]?.minY == -40)
        #expect(model.position.point == nil && !model.position.isPositionedByUser)
        runtime.scrollWheel(by: CGSize(width: 0, height: 20), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        #expect(model.position.isPositionedByUser)
        #expect(model.position.viewID(type: Int.self) == 3)
    }

    @Test func pagingSettlesOnePageInTheDirectionOfTheFlick() {
        let runtime = Runtime()
        runtime.mount(Pages())
        runtime.layout(in: size)
        runtime.pointerDown(at: CGPoint(x: 250, y: 100), type: .touch, time: 0)
        runtime.pointerMoved(to: CGPoint(x: 130, y: 100), time: 0.05)     // a fast flick left
        runtime.pointerUp(at: CGPoint(x: 130, y: 100), time: 0.06)
        settled(runtime)
        #expect(runtime.probeFrames["p1"]?.minX == 0)
        // A small drag back settles on the nearest page: the same one.
        runtime.pointerDown(at: CGPoint(x: 100, y: 100), type: .touch, time: 1)
        runtime.pointerMoved(to: CGPoint(x: 130, y: 100), time: 1.3)
        runtime.pointerUp(at: CGPoint(x: 130, y: 100), time: 1.6)
        settled(runtime)
        #expect(runtime.probeFrames["p1"]?.minX == 0)
    }

    @Test func viewAlignedSettlesOnTheNearestTarget() {
        let runtime = Runtime()
        runtime.mount(ScrollView { VStack(spacing: 0) { Rows(height: 50) }.scrollTargetLayout() }.scrollTargetBehavior(.viewAligned))
        runtime.layout(in: size)
        runtime.scrollWheel(by: CGSize(width: 0, height: 70), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["row0"]?.minY == -70)
        // The wheel goes quiet: the content settles with row 1 at the top.
        settled(runtime)
        #expect(runtime.probeFrames["row1"]?.minY == 0)
        // A long flick is limited to one view at a time by `.always`.
        let limited = Runtime()
        limited.mount(ScrollView { VStack(spacing: 0) { Rows(height: 50) }.scrollTargetLayout() }.scrollTargetBehavior(.viewAligned(limitBehavior: .always)))
        limited.layout(in: size)
        limited.pointerDown(at: CGPoint(x: 150, y: 180), type: .touch, time: 0)
        limited.pointerMoved(to: CGPoint(x: 150, y: 60), time: 0.05)
        limited.pointerUp(at: CGPoint(x: 150, y: 60), time: 0.06)
        settled(limited)
        #expect(limited.probeFrames["row1"]?.minY == 0)
    }

    @Test func phasesFollowAPan() {
        let model = PositionModel()
        let runtime = Runtime()
        runtime.mount(Phased(model: model))
        runtime.layout(in: size)
        runtime.layout(in: size)
        #expect(model.log == ["idle→idle"])
        runtime.pointerDown(at: CGPoint(x: 150, y: 150), type: .touch, time: 0)
        runtime.layout(in: size)
        #expect(model.log.last == "idle→tracking")
        runtime.pointerMoved(to: CGPoint(x: 150, y: 100), time: 0.02)
        runtime.layout(in: size)
        #expect(model.log.last == "tracking→interacting")
        runtime.pointerUp(at: CGPoint(x: 150, y: 100), time: 0.03)
        runtime.layout(in: size)
        #expect(model.log.last == "interacting→decelerating")
        settled(runtime)
        #expect(model.log.last == "decelerating→idle")
        // A tap that never pans goes tracking and back to idle.
        runtime.pointerDown(at: CGPoint(x: 150, y: 150), type: .touch, time: 2)
        runtime.pointerUp(at: CGPoint(x: 150, y: 150), time: 2.05)
        runtime.layout(in: size)
        #expect(model.log.suffix(2) == ["idle→tracking", "tracking→idle"])
    }

    @Test func geometryReportsTheInsetOffset() {
        let model = PositionModel()
        let runtime = Runtime()
        runtime.mount(Geometry(model: model))
        runtime.layout(in: size)
        runtime.layout(in: size)
        // The empty geometry's value first, then the real one: −20 under a 20 pt margin.
        #expect(model.log == ["0.0", "-20.0"])
        runtime.scrollWheel(by: CGSize(width: 0, height: 30), at: CGPoint(x: 150, y: 100))
        // The scrolled frame moves the content and queues the action; the next frame runs it.
        runtime.layout(in: size)
        runtime.layout(in: size)
        #expect(model.log.last == "10.0")
    }

    @Test func flashTriggerShowsTheIndicators() {
        let model = PositionModel()
        let runtime = Runtime()
        runtime.mount(Flashing(model: model))
        runtime.layout(in: CGSize(width: 100, height: 200))
        #expect(!runtime.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("fillRRect") })
        model.flash += 1
        runtime.layout(in: CGSize(width: 100, height: 200))
        let knobs = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillRRect") }
        // The halo then the core: 7 pt wide, 2 pt from the trailing edge, 4 pt from the top.
        #expect(knobs.count == 2)
        #expect(knobs.last?.hasPrefix("fillRRect(91, 4, 7, ") == true)
    }

    @Test func iOSPanDismissesTheKeyboard() {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        let text = Binding.constant("")
        runtime.mount(ScrollView { VStack(spacing: 0) { TextField("Name", text: text)._probe("field"); Rows(count: 50) } })
        runtime.layout(in: size)
        let field = runtime.probeFrames["field"]!
        runtime.pointerDown(at: CGPoint(x: field.midX, y: field.midY), type: .touch, time: 0)
        runtime.pointerUp(at: CGPoint(x: field.midX, y: field.midY), time: 0.05)
        runtime.layout(in: size)
        #expect(runtime.focusedTextFieldIdentifier != nil)
        runtime.pointerDown(at: CGPoint(x: 150, y: 150), type: .touch, time: 1)
        runtime.pointerMoved(to: CGPoint(x: 150, y: 100), time: 1.02)
        runtime.pointerUp(at: CGPoint(x: 150, y: 100), time: 1.5)
        runtime.layout(in: size)
        #expect(runtime.focusedTextFieldIdentifier == nil)
        // `.never` keeps the keyboard.
        let kept = Runtime(environment: environment)
        kept.mount(ScrollView { VStack(spacing: 0) { TextField("Name", text: text)._probe("field"); Rows(count: 50) } }.scrollDismissesKeyboard(.never))
        kept.layout(in: size)
        let keptField = kept.probeFrames["field"]!
        kept.pointerDown(at: CGPoint(x: keptField.midX, y: keptField.midY), type: .touch, time: 0)
        kept.pointerUp(at: CGPoint(x: keptField.midX, y: keptField.midY), time: 0.05)
        kept.layout(in: size)
        kept.pointerDown(at: CGPoint(x: 150, y: 150), type: .touch, time: 1)
        kept.pointerMoved(to: CGPoint(x: 150, y: 100), time: 1.02)
        kept.pointerUp(at: CGPoint(x: 150, y: 100), time: 1.5)
        kept.layout(in: size)
        #expect(kept.focusedTextFieldIdentifier != nil)
    }
}
