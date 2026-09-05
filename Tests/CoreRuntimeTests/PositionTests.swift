// Phase 6: `position` (the proposed size, child centred at the point) and the safe-area
// modifiers (plain content shrinks, scroll views keep their frame and inset their content,
// `ignoresSafeArea` extends).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PositionTests {
    private func frames<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100)) -> [String] {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillRect") }
    }

    @Test func positionTakesTheProposalAndCentresTheChild() {
        // In a fixed 200 × 100 box the position view fills it; the 20 × 10 child is centred at (50, 30).
        #expect(frames(Color.red.frame(width: 20, height: 10).position(x: 50, y: 30)) == ["fillRect(40, 25, 20, 10) #FF383C"])
        #expect(frames(Color.red.frame(width: 20, height: 10).position(CGPoint(x: 50, y: 30))) == ["fillRect(40, 25, 20, 10) #FF383C"])
        // In a stack it is flexible: the remaining height goes to it, and the point is relative to it.
        let stacked = frames(VStack(spacing: 0) {
            Color.blue.frame(width: 20, height: 20)
            Color.red.frame(width: 20, height: 10).position(x: 10, y: 10)
        })
        #expect(stacked == ["fillRect(90, 0, 20, 20) #0088FF", "fillRect(0, 25, 20, 10) #FF383C"])
        // The child may land outside the frame.
        #expect(frames(Color.red.frame(width: 20, height: 10).position(x: -10, y: 300)) == ["fillRect(-20, 295, 20, 10) #FF383C"])
    }

    @Test func safeAreaInsetShrinksPlainContentAndInsetsScrollViews() {
        // A 30 pt bar at the bottom with the default 8 pt spacing: the content keeps 62 pt.
        let plain = frames(Color.red.safeAreaInset(edge: .bottom) { Color.blue.frame(height: 30) })
        #expect(plain == ["fillRect(0, 0, 200, 62) #FF383C", "fillRect(0, 70, 200, 30) #0088FF"])
        // Explicit spacing, a top edge, and the inset aligned across it.
        let top = frames(Color.red.safeAreaInset(edge: .top, alignment: .leading, spacing: 0) { Color.blue.frame(width: 40, height: 20) })
        #expect(top == ["fillRect(0, 20, 200, 80) #FF383C", "fillRect(0, 0, 40, 20) #0088FF"])
        let leading = frames(Color.red.safeAreaInset(edge: .leading, spacing: 4) { Color.blue.frame(width: 30) })
        #expect(leading == ["fillRect(34, 0, 166, 100) #FF383C", "fillRect(0, 0, 30, 100) #0088FF"])
        // A scroll view keeps its 100 pt frame; its content starts under the top bar and scrolls
        // 30 + 8 pt further at the bottom.
        let runtime = Runtime()
        runtime.mount(ScrollView {
            VStack(spacing: 0) { ForEach(0..<5, id: \.self) { _ in Color.green.frame(height: 40) } }._probe("content")
        }.safeAreaInset(edge: .top, spacing: 0) { Color.blue.frame(height: 20) }.safeAreaInset(edge: .bottom) { Color.blue.frame(height: 30) }._probe("scroll"))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let scrolled = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillRect") }
        #expect(scrolled.first == "fillRect(0, 20, 200, 40) #34C759")
        #expect(scrolled.contains("fillRect(0, 70, 200, 30) #0088FF") && scrolled.contains("fillRect(0, 0, 200, 20) #0088FF"))
        #expect(runtime.probeFrames["scroll"] == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(runtime.probeFrames["content"] == CGRect(x: 0, y: 20, width: 200, height: 200))
        // The scrollable range is the content plus both insets: 200 + 20 + 38 − 100.
        runtime.scrollWheel(by: CGSize(width: 0, height: 1000), at: CGPoint(x: 100, y: 50))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["content"] == CGRect(x: 0, y: -138, width: 200, height: 200))
    }

    @Test func safeAreaPaddingAndIgnoresSafeArea() {
        #expect(frames(Color.red.safeAreaPadding(20)) == ["fillRect(20, 20, 160, 60) #FF383C"])
        #expect(frames(Color.red.safeAreaPadding(.horizontal, 10)) == ["fillRect(10, 0, 180, 100) #FF383C"])
        #expect(frames(Color.red.safeAreaPadding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))) == ["fillRect(2, 1, 194, 96) #FF383C"])
        // ignoresSafeArea keeps the full bounds under the bar; edges can be chosen.
        let ignoring = frames(Color.red.ignoresSafeArea().safeAreaInset(edge: .bottom) { Color.blue.frame(height: 30) })
        #expect(ignoring == ["fillRect(0, 0, 200, 100) #FF383C", "fillRect(0, 70, 200, 30) #0088FF"])
        #expect(frames(Color.red.edgesIgnoringSafeArea(.all).safeAreaPadding(20)) == ["fillRect(0, 0, 200, 100) #FF383C"])
        // Painting modifiers pass the safe area through; a frame does not.
        #expect(frames(Color.red.ignoresSafeArea().opacity(0.9).safeAreaPadding(20)).contains("fillRect(0, 0, 200, 100) #FF383C"))
        #expect(frames(Color.red.ignoresSafeArea().frame(width: 100).safeAreaPadding(20)) == ["fillRect(50, 20, 100, 60) #FF383C"])
        // Nothing proposed: the insets add to the content's size.
        let sized = Runtime()
        sized.mount(Color.red.frame(width: 20, height: 10).safeAreaPadding(5).fixedSize())
        sized.layout(in: CGSize(width: 200, height: 100))
        #expect(sized.render(scale: 2).commands.map(\.description) == ["fillRect(90, 45, 20, 10) #FF383C"])
    }
}
#endif
