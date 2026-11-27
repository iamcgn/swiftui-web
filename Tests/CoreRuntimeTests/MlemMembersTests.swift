// SwiftUI members Mlem calls: a rich-text editor over an attributed string, the typesetting
// language, iOS 27.1's toolbar axes, and a chart scale whose domain is given as values.
import Testing
import Foundation
import SwiftUI
@testable import SwiftUIWebCore
import SwiftUIWebHeadless
import Charts

#if !os(WASI)
@Suite @MainActor struct MlemMembersTests {
    @Test func anAttributedEditorEditsTheCharacters() {
        var styled = AttributedString("Hello")
        styled.link = URL(string: "https://lemmy.world")
        var value = styled
        let editor = TextEditor(text: Binding(get: { value }, set: { value = $0 }))
        #expect(editor.text.wrappedValue == "Hello")
        editor.text.wrappedValue = "Hello"
        #expect(value == styled)   // unchanged text keeps its attributes
        editor.text.wrappedValue = "Hello there"
        // The edit is only the new characters, so the link stays on "Hello" (#435).
        #expect(String(value.characters) == "Hello there")
        #expect(value.runs.map { String(value[$0.range].characters) } == ["Hello", " there"])
        #expect(value.runs.map { $0.link } == [URL(string: "https://lemmy.world"), nil])
        editor.text.wrappedValue = "Hey there"
        #expect(value.runs.map { String(value[$0.range].characters) } == ["He", "y there"])
        #expect(value.runs.map { $0.link } == [URL(string: "https://lemmy.world"), nil])
    }

    @Test func anEditInTheMiddleKeepsBothEnds() {
        var styled = AttributedString("ab")
        styled.link = URL(string: "https://a.example")
        var tail = AttributedString("cd")
        tail.link = URL(string: "https://c.example")
        styled.append(tail)
        let edited = TextEditor.editing(styled, to: "abXcd")
        #expect(String(edited.characters) == "abXcd")
        #expect(edited.runs.map { $0.link } == [URL(string: "https://a.example"), nil, URL(string: "https://c.example")])
        #expect(TextEditor.editing(styled, to: "") == AttributedString(""))
        #expect(String(TextEditor.editing(AttributedString(""), to: "new").characters) == "new")
    }

    @Test func typesettingAndToolbarAxesAreAccepted() {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(Text("Title").typesettingLanguage(.init(languageCode: .english)))
        runtime.layout(in: CGSize(width: 200, height: 40))
        #expect(!runtime.render(scale: 1).commands.isEmpty)
        #expect(EnvironmentValues().toolbarVerticalEdge == nil)
        let items = ToolbarItem(placement: .bottomBar) { Text("Sort") }.axisBehavior(.verticalPreferred)
        #expect(items._toolbarItems.count == 1)
        let customizable = ToolbarItem(id: "sort", placement: .bottomBar) { Text("Sort") }.axisBehavior(.horizontalOnly)
        #expect(customizable._toolbarItems.count == 1)
    }

    @Test func aDomainOfValuesSpansThem() {
        func labels(_ chart: some View) -> [String] {
            let runtime = Runtime()
            runtime.textEngine = MetricsTextEngine()
            runtime.mount(chart.frame(width: 320, height: 240))
            runtime.layout(in: CGSize(width: 320, height: 240))
            return runtime.render(scale: 2).commands.compactMap { command in
                if case .drawText(let string, _, _, _) = command { return string }
                return nil
            }
        }
        let bars = Chart {
            BarMark(x: .value("Day", "Mon"), y: .value("Ms", 120))
            BarMark(x: .value("Day", "Tue"), y: .value("Ms", 340))
        }
        let ranged = labels(bars.chartYScale(domain: 0...1000))
        #expect(labels(bars.chartYScale(domain: [0, max(1000, 340 + 100)])) == ranged)
        #expect(labels(bars.chartYScale(domain: [1000.0, 0.0])) == ranged)
        #expect(labels(bars.chartYScale(domain: [Int]())) == labels(bars))
    }
}
#endif
