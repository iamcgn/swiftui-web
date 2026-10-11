// The container APIs (sw-subviews, Docs/elements/ForEach.md): how a view resolves into subviews
// and sections, their identities and container values; the layouts are held by the goldens
// (`foreach/subviews`, `foreach/subviews-foreach`, `foreach/sections`, `foreach/container-values`).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
extension ContainerValues {
    @Entry var testWeight: Int = 1
}

@Suite @MainActor struct SubviewsTests {
    struct Pair: View {
        var body: some View {
            Text("a")
            Text("b")
        }
    }

    struct Single: View {
        @State private var count = 0
        var body: some View { Button("tap") { count += 1 } }
    }

    private func count<V: View>(_ view: V) -> Int { _Subviews.subviews(of: view).count }

    @Test func tuplesConditionalsForEachAndGroupsFlatten() {
        let view = TupleView((Text("a"), ForEach(0..<3) { Text("\($0)") }, Group { Text("g1"); Text("g2") }.padding(), Optional<Text>.none, EmptyView()))
        let subviews = _Subviews.subviews(of: view)
        #expect(subviews.count == 6)
        // Identity: ForEach elements by their id, tuple children by index, `id(_:)` explicitly.
        #expect(subviews[1].id == Subview.ID(value: 0) && subviews[3].id == Subview.ID(value: 2))
        #expect(subviews[0].id == Subview.ID(value: 0) && subviews[4].id == Subview.ID(value: 4))
        #expect(_Subviews.subviews(of: Text("x").id("custom"))[0].id == Subview.ID(value: "custom"))
        // A conditional contributes its branch; a custom view with a multi-child body its children.
        let branch = _ConditionalContent<Text, TupleView<(Text, Text)>>(storage: .falseContent(TupleView((Text("f1"), Text("f2")))))
        #expect(count(branch) == 2 && count(Pair()) == 2 && count(AnyView(Pair())) == 2)
        // A view whose body comes to one piece stays itself (its state and style intact).
        #expect(count(Single()) == 1 && count(Button("x") {}) == 1 && count(Text("t")) == 1)
        #expect(_Subviews.subviews(of: Single())[0].content.storage.viewType == Single.self)
        // Slices and the collection are views over their elements.
        #expect(subviews.dropFirst().count == 5 && subviews[1...2].count == 2)
    }

    @Test func containerValuesAndTags() {
        let view = TupleView((Text("a").containerValue(\.testWeight, 7), Text("b").tag("beta"), Group { Text("c"); Text("d").tag(4) }.containerValue(\.testWeight, 2).tag(9)))
        let subviews = _Subviews.subviews(of: view)
        #expect(subviews.map { $0.containerValues.testWeight } == [7, 1, 2, 2])
        #expect(subviews[1].containerValues.tag(for: String.self) == "beta" && subviews[1].containerValues.hasTag("beta") && !subviews[1].containerValues.hasTag("x"))
        // A tag on the group reaches every child; a child's own tag inside is replaced by the outer one.
        #expect(subviews[2].containerValues.tag(for: Int.self) == 9 && subviews[3].containerValues.tag(for: Int.self) == 9)
        #expect(subviews[0].containerValues.tag(for: Int.self) == nil && ContainerValues().testWeight == 1)
    }

    @Test func sectionsGatherHeadersContentAndLooseRows() {
        let view = TupleView((
            Section { Text("a"); Text("b") } header: { Text("H") } footer: { Text("F") },
            Text("loose1"), Text("loose2"),
            Section("Second") { ForEach(["x", "y"], id: \.self) { Text($0) } },
            Text("tail")
        ))
        let sections = _Subviews.sections(of: view)
        #expect(sections.count == 4)
        #expect(sections[0].header.count == 1 && sections[0].content.count == 2 && sections[0].footer.count == 1)
        #expect(sections[1].header.isEmpty && sections[1].content.count == 2 && sections[1].footer.isEmpty)
        #expect(sections[2].header.count == 1 && sections[2].content.count == 2 && sections[2].content[1].id == Subview.ID(value: "y"))
        #expect(sections[3].content.count == 1)
        // The subviews form sees through sections.
        #expect(_Subviews.subviews(of: view).count == 10)   // headers, rows and footers alike
    }

    @Test func theContainersRenderTheirTransforms() {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(Group(subviews: Pair()) { subviews in
            HStack(spacing: 0) {
                ForEach(subviews) { subview in Color.red.frame(width: 10, height: 10)._probe("box-\(subview.id.value)") }
                Color.blue.frame(width: CGFloat(subviews.count) * 5, height: 10)._probe("count")
            }
        })
        runtime.layout(in: CGSize(width: 100, height: 50))
        #expect(runtime.probeFrames["count"]?.width == 10 && runtime.probeFrames["box-0"] != nil && runtime.probeFrames["box-1"] != nil)
        let sections = Runtime()
        sections.textEngine = RecordedTextEngine(entries: [:])
        sections.mount(ForEach(sections: TupleView((Section("S") { Text("a") }, Text("b")))) { section in
            Color.green.frame(width: CGFloat(section.content.count + section.header.count) * 10, height: 10)._probe("s-\(section.id.value)")
        })
        sections.layout(in: CGSize(width: 100, height: 50))
        #expect(sections.probeFrames["s-0"]?.width == 20 && sections.probeFrames["s-1"]?.width == 10)
    }
}
#endif
