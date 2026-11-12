// iOS toolbar items read the environment where their `toolbar` modifier sits (SimpleToDo, decision
// 0021): an `environment(\.editMode, $editMode)` outside `toolbar` reaches the bar's `EditButton`,
// which turns to Done; `disabled` on a bar item is the element's notEnabled trait; a `.bottomBar`
// item shows in a band at the bottom of the stack while its content shows anything.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct IOSToolbarEnvironmentTests {
    final class ProportionalTextEngine: TextEngine {
        func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
            let string = runs.map(\.string).joined()
            let size = runs.first?.font.size ?? 17
            let w = CGFloat(string.count) * size * 0.55
            let height = size * 1.3, baseline = size
            let line = TextLayout.Line(range: string.startIndex..<string.endIndex, width: w, baseline: baseline, fragments: [TextLayout.Fragment(text: string, run: 0, x: 0, width: w)])
            return TextLayout(size: CGSize(width: w, height: height), firstBaseline: baseline, lastBaseline: baseline, lines: [line])
        }
        func metrics(for font: ResolvedFont) -> FontMetrics { FontMetrics(lineHeight: font.size * 1.3, spacingBelow: 0, spacingAbove: 0, textToText: 0) }
    }

    private let size = CGSize(width: 375, height: 667)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = ProportionalTextEngine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func element(_ r: Runtime, _ label: String) -> SemanticsNode? {
        r.semanticsTree().first { $0.label == label }
    }

    struct Screen: View {
        @State private var editMode = EditMode.inactive
        @State private var items = ["Milk", "Bread"]

        var body: some View {
            NavigationStack {
                List {
                    ForEach(items, id: \.self) { Text($0) }
                }
                .navigationTitle("Items")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                            .disabled(items.isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        if editMode == .active {
                            HStack {
                                Spacer()
                                Button("Delete all") {
                                    items.removeAll()
                                    editMode = .inactive
                                }
                            }
                        }
                    }
                }
                .environment(\.editMode, $editMode)
            }
        }
    }

    @Test func editButtonInTheBarReadsTheEditModeSetOutsideTheToolbar() throws {
        let r = runtime(Screen())
        let edit = try #require(element(r, "Edit"))
        #expect(edit.isEnabled)
        #expect(element(r, "Delete all") == nil)   // the bottom item's content is empty

        r.activate(semanticsIdentifier: edit.identifier)
        r.layout(in: size)
        #expect(element(r, "Edit") == nil)
        let done = try #require(element(r, "Done"))
        #expect(done.frame.minY < 100)

        // The bottom bar shows now, its button at the trailing end of the band at the bottom.
        let delete = try #require(element(r, "Delete all"))
        #expect(delete.frame.minY > size.height - PlatformMetrics.searchBandHeight)
        #expect(delete.frame.maxY < size.height)
        #expect(delete.frame.maxX > size.width - PlatformMetrics.navigationBarItemInset - 1)

        r.activate(semanticsIdentifier: delete.identifier)
        r.layout(in: size)
        #expect(element(r, "Delete all") == nil)
        let disabled = try #require(element(r, "Edit"))
        #expect(!disabled.isEnabled)
    }

    @Test func aDisabledButtonIsNotEnabledInTheSemantics() throws {
        let r = runtime(VStack {
            Button("On") {}
            Button("Off") {}.disabled(true)
        })
        #expect(try #require(element(r, "On")).isEnabled)
        #expect(try !#require(element(r, "Off")).isEnabled)
    }
}
#endif
