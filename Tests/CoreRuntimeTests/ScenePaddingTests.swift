// `scenePadding(_:)` as BackyardBirds titles its backyard cards: the system's default padding on
// the edges it names, as `padding(_:)` with no length gives.
import Testing
import SwiftUI

@Suite @MainActor struct ScenePaddingTests {
    private func frames<V: View>(_ view: V) -> [String: CGRect] {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 200))
        return runtime.probeFrames
    }

    @Test func scenePaddingIsTheDefaultPadding() {
        let scene = frames(Color.red.frame(width: 10, height: 10).scenePadding(.horizontal)._probe("p"))["p"]
        let plain = frames(Color.red.frame(width: 10, height: 10).padding(.horizontal)._probe("p"))["p"]
        #expect(scene != nil && scene == plain)
        #expect(scene?.height == 10 && (scene?.width ?? 0) > 10)
        let all = frames(Color.red.frame(width: 10, height: 10).scenePadding()._probe("p"))["p"]
        #expect(all == frames(Color.red.frame(width: 10, height: 10).padding()._probe("p"))["p"])
        let minimum = frames(Color.red.frame(width: 10, height: 10).scenePadding(.minimum, edges: .vertical)._probe("p"))["p"]
        #expect(minimum == frames(Color.red.frame(width: 10, height: 10).padding(.vertical)._probe("p"))["p"])
    }
}
