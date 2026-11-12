// iOS edit mode in a list with a multiple selection (SimpleToDo, decision 0021): a press on a row
// toggles its selection rather than following the row's NavigationLink, and a row's `tag` is
// what the selection holds when the selection takes the tag's type (rows identified by the
// items' ids, a `Set` of the items themselves).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct IOSListEditSelectionTests {
    struct Item: Identifiable, Hashable {
        var id: Int
        var title: String
    }

    @Observable final class Model {
        var selected = Set<Item>()
        var editMode = EditMode.active
        var items = [Item(id: 1, title: "Milk"), Item(id: 2, title: "Bread")]
    }

    struct Screen: View {
        let model: Model
        var body: some View {
            NavigationStack {
                List(selection: Binding(get: { model.selected }, set: { model.selected = $0 })) {
                    ForEach(model.items) { item in
                        NavigationLink { Text("Detail \(item.title)") } label: { Text(item.title) }
                            .tag(item)
                    }
                }
                .navigationTitle("Items")
                .environment(\.editMode, Binding(get: { model.editMode }, set: { model.editMode = $0 }))
            }
        }
    }

    private let size = CGSize(width: 375, height: 667)

    private func runtime(_ model: Model) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = IOSToolbarEnvironmentTests.ProportionalTextEngine()
        runtime.mount(Screen(model: model))
        runtime.layout(in: size)
        return runtime
    }

    private func press(_ r: Runtime, _ label: String) throws {
        let frame = try #require(r.semanticsTree().first { $0.label == label }).frame
        let point = CGPoint(x: frame.midX, y: frame.midY)
        r.pointerDown(at: point)
        r.pointerUp(at: point)
        r.layout(in: size)
    }

    private func labels(_ r: Runtime) -> [String] { r.semanticsTree().map(\.label) }

    @Test func aPressInEditModeTogglesTheTaggedItemAndDoesNotPush() throws {
        let model = Model()
        let r = runtime(model)
        try press(r, "Milk")
        #expect(model.selected == [model.items[0]])
        #expect(!labels(r).contains("Detail Milk"))
        try press(r, "Bread")
        #expect(model.selected == Set(model.items))
        try press(r, "Milk")
        #expect(model.selected == [model.items[1]])
    }

    @Test func outsideEditModeThePressPushes() throws {
        let model = Model()
        model.editMode = .inactive
        let r = runtime(model)
        try press(r, "Milk")
        #expect(labels(r).contains("Detail Milk"))
    }
}
#endif
