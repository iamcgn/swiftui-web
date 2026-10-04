// Phase 8 step 6, sw-disclosure: the row's press animates the expansion (the group grows while
// the content fades in) (Docs/elements/DisclosureGroup.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Observable private final class Model { var expanded = false }

private struct Group: View {
    let model: Model
    var body: some View {
        VStack(spacing: 0) {
            DisclosureGroup("Details", isExpanded: Binding(get: { model.expanded }, set: { model.expanded = $0 })) {
                Color.red.frame(width: 40, height: 40)._probe("inside")
            }
            ._probe("group")
            Text("Below")._probe("below")
        }
    }
}

@Suite @MainActor struct DisclosureAnimationTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    @Test func pressingTheRowAnimatesTheExpansion() {
        let model = Model()
        let runtime = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for word in ["Details", "Below"] {
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: 40, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(Group(model: model))
        runtime.layout(in: CGSize(width: 200, height: 200))
        let collapsed = runtime.probeFrames["below"]!
        let row = runtime.probeFrames["group"]!
        runtime.pointerDown(at: CGPoint(x: row.minX + 20, y: row.midY))
        runtime.pointerUp(at: CGPoint(x: row.minX + 20, y: row.midY))
        runtime.layout(in: CGSize(width: 200, height: 200))
        // The binding flipped under an animation: the group is 40 taller (its frames tween) and
        // the content fades in.
        #expect(model.expanded && runtime.isAnimating)
        #expect(runtime.probeFrames["group"]!.height == row.height + 40)
        _ = runtime.advanceAnimations(elapsed: 0.1)
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("beginGroup(opacity:") })
        _ = runtime.advanceAnimations(elapsed: 2)
        #expect(!runtime.isAnimating)
        // A binding changed outside a transaction snaps.
        model.expanded = false
        runtime.layout(in: CGSize(width: 200, height: 200))
        #expect(!runtime.isAnimating && runtime.probeFrames["below"]!.minY == collapsed.minY && runtime.probeFrames["group"]!.height == row.height)
    }
}
#endif
