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
        #expect(String(value.characters) == "Hello there" && value.runs.count == 1 && value.runs.first?.link == nil)
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
