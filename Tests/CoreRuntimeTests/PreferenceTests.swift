// Phase 1 step 8: preferences, GeometryReader, coordinate spaces.
import Testing
import SwiftUI

private struct CountKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

private struct NamesKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}

private struct RectKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

@MainActor
private final class Box { var value: Int? ; var names: [String] = []; var calls = 0 }

@Suite @MainActor struct PreferenceTests {
    @Test func preferencesReduceAcrossSiblingsAndOverrideSubtrees() {
        let box = Box()
        let runtime = Runtime()
        runtime.mount(
            VStack {
                Color.red.preference(key: CountKey.self, value: 1)
                HStack {
                    Color.red.preference(key: CountKey.self, value: 2)
                    Color.red.preference(key: CountKey.self, value: 3)
                }
                .preference(key: CountKey.self, value: 10)       // replaces the subtree's 5
                Color.red.preference(key: CountKey.self, value: 4).transformPreference(CountKey.self) { $0 *= 100 }
                Color.red                                           // writes nothing: skipped, not defaulted
            }
            .onPreferenceChange(CountKey.self) { box.value = $0; box.calls += 1 })
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(box.value == 411)
        #expect(box.calls == 1)

        // Unchanged value: no call. Changed content: one call.
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(box.calls == 1)
    }

    @Test func orderedReductionAndDefault() {
        let box = Box()
        let runtime = Runtime()
        runtime.mount(
            HStack {
                Color.red.preference(key: NamesKey.self, value: ["a"])
                Color.red.background(Color.blue.preference(key: NamesKey.self, value: ["bg"]))
                Color.red.overlay(Color.blue.preference(key: NamesKey.self, value: ["ov"]))
                    .preference(key: NamesKey.self, value: ["c"])
            }
            .onPreferenceChange(NamesKey.self) { box.names = $0 })
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(box.names == ["a", "bg", "c"])

        let empty = Runtime()
        empty.mount(Color.red.onPreferenceChange(NamesKey.self) { box.names = $0 })
        empty.layout(in: CGSize(width: 10, height: 10))
        #expect(box.names == [])
    }

    @Test func geometryReaderReportsSizeAndFrames() throws {
        final class Seen: @unchecked Sendable { var size = CGSize.zero; var local = CGRect.zero; var global = CGRect.zero; var named = CGRect.zero; var bounds: CGRect? }
        let seen = Seen()
        let runtime = Runtime()
        runtime.mount(
            VStack(spacing: 0) {
                Color.red.frame(height: 30)
                HStack(spacing: 0) {
                    Color.blue.frame(width: 20)
                    GeometryReader { proxy in
                        let _ = { @MainActor in
                            seen.size = proxy.size
                            seen.local = proxy.frame(in: .local)
                            seen.global = proxy.frame(in: .global)
                            seen.named = proxy.frame(in: .named("outer"))
                            seen.bounds = proxy.bounds(of: .named("outer"))
                        }()
                        Color.green._probe("inner")
                    }
                    ._probe("reader")
                }
                .padding(.leading, 5)
                .coordinateSpace(name: "outer")
            }
            .frame(width: 100, height: 100))
        runtime.layout(in: CGSize(width: 200, height: 200))
        let f = runtime.probeFrames
        #expect(f["reader"] == CGRect(x: 75, y: 80, width: 75, height: 70))
        #expect(seen.size == CGSize(width: 75, height: 70))
        #expect(seen.local == CGRect(x: 0, y: 0, width: 75, height: 70))
        #expect(seen.global == CGRect(x: 75, y: 80, width: 75, height: 70))
        #expect(seen.named == CGRect(x: 25, y: 0, width: 75, height: 70))
        #expect(seen.bounds == CGRect(x: -25, y: 0, width: 100, height: 70))
        // The reader fills its proposal and places its content at the top-leading corner.
        #expect(f["inner"] == f["reader"])
    }

    @Test func geometryReaderIsFlexibleWithTenPointIdeal() {
        let runtime = Runtime()
        runtime.mount(GeometryReader { _ in Color.red }.fixedSize()._probe("fixed"))
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(runtime.probeFrames["fixed"] == CGRect(x: 45, y: 45, width: 10, height: 10))
    }

    @Test func geometryReaderRelayoutsOnSizeChange() {
        struct Sizer: View {
            @State var wide = false
            var body: some View {
                GeometryReader { proxy in
                    Color.red.frame(width: proxy.size.width / 2)._probe("half")
                }
                .frame(width: wide ? 80 : 40, height: 10)
            }
        }
        let runtime = Runtime()
        let node = runtime.mount(Sizer()) as! CompositeNode<Sizer>
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(runtime.probeFrames["half"]?.width == 20)
        node.view.wide = true
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(runtime.probeFrames["half"]?.width == 40)
    }

    @Test func probeThroughPreferencesMatchesDirectProbe() throws {
        // Both mechanisms must agree, since fixtures use the preference form and debugging the direct form.
        let box = Box()
        var frames: [String: CGRect] = [:]
        let runtime = Runtime()
        runtime.mount(
            HStack(spacing: 4) {
                Color.red.frame(width: 30, height: 20)._probe("direct")
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: RectKey.self, value: proxy.frame(in: .global))
                    })
                Color.blue.frame(width: 30, height: 20)
            }
            .onPreferenceChange(RectKey.self) { frames["viaPreference"] = $0; box.calls += 1 })
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(frames["viaPreference"] == runtime.probeFrames["direct"])
        #expect(frames["viaPreference"] == CGRect(x: 18, y: 40, width: 30, height: 20))
    }
}
