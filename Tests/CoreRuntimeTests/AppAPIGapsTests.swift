// Phase 10 item 3 (decision 0021): the API the surveyed apps reach for — the scene environment
// modifiers, the error and `presenting:` alerts, `Button(systemImage:)`, `Transaction(animation:)`,
// `.spring()`, and the deprecated forms (`navigationBarTitle`, `sizeCategory`, `colorScheme(_:)`,
// `EnvironmentalModifier`, `NavigationView`).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebCombine

@Suite @MainActor struct AppAPIGapsTests {
    final class Store: ObservableObject { @Published var name = "store" }
    @Observable final class Model { var title = "model" }

    struct Leaf: View {
        @EnvironmentObject var store: Store
        @Environment(Model.self) var model
        @Environment(\.lineLimit) var limit
        var body: some View { Text("\(store.name) \(model.title) \(limit ?? 0)") }
    }
    struct Demo: App {
        static let store = Store()
        static let model = Model()
        var body: some Scene {
            WindowGroup { Leaf() }
                .environmentObject(Demo.store)
                .environment(Demo.model)
                .environment(\.lineLimit, 3)
        }
    }

    private func texts(_ runtime: Runtime) -> [String] {
        runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }
    }

    @Test func sceneEnvironmentReachesTheRoots() {
        let runtime = Runtime()
        runtime.mount(Demo._rootView())
        runtime.layout(in: CGSize(width: 300, height: 100))
        #expect(texts(runtime) == ["store model 3"])
    }

    @Test func errorAndPresentingAlerts() {
        struct Failure: LocalizedError { var errorDescription: String? { "Could not save." } }
        let runtime = Runtime()
        let failure: Failure? = Failure()
        runtime.mount(
            Text("root")
                .alert(isPresented: .constant(true), error: failure, actions: { _ in Button("Retry") {} }, message: { Text($0.errorDescription ?? "") })
        )
        runtime.layout(in: CGSize(width: 300, height: 300))
        let shown = texts(runtime) + runtime.presentations.flatMap { presentation in
            presentation.content.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }
        }
        #expect(shown.contains("Could not save.") && shown.contains("Retry"))

        let presenting = Runtime()
        presenting.mount(Text("root").alert("Delete?", isPresented: .constant(true), presenting: 7 as Int?, actions: { Button("Delete \($0)") {} }))
        presenting.layout(in: CGSize(width: 300, height: 300))
        let actions = presenting.presentations.flatMap { $0.content.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString } }
        #expect(actions.contains("Delete 7") && actions.contains("Delete?"))
    }

    @Test func buttonsWithSystemImagesAndTheSmallForms() {
        let runtime = Runtime()
        runtime.mount(VStack {
            Button("Add", systemImage: "plus") {}
            Button("Trash", systemImage: "trash", role: .destructive) {}
        })
        runtime.layout(in: CGSize(width: 300, height: 100))
        #expect(texts(runtime) == ["Add", "Trash"])
        let transaction = Transaction(animation: .spring())
        #expect(transaction.animation != nil && Animation.spring() == Animation.spring(duration: 0.5, bounce: 0))
        let transition: AnyTransition = .modifier(active: EmptyModifier(), identity: EmptyModifier())
        #expect(transition.effects(insertion: true).isIdentity)
    }

    // Deprecated API in a deprecated context: no warnings (the package treats them as errors).
    @available(*, deprecated)
    @Test func deprecatedFormsMapOntoTheCurrentAPI() {
        struct Shout: EnvironmentalModifier {
            func resolve(in environment: EnvironmentValues) -> some ViewModifier { _Shouted(limit: environment.lineLimit ?? 1) }
        }
        struct _Shouted: ViewModifier {
            let limit: Int
            func body(content: Content) -> some View { content.lineLimit(limit * 2) }
        }
        @available(*, deprecated)
        struct Reader: View {
            @Environment(\.lineLimit) var limit
            @Environment(\.sizeCategory) var category
            @Environment(\.colorScheme) var scheme
            var body: some View { Text("\(limit ?? 0) \(category == .extraLarge ? "XL" : "?") \(scheme == .dark ? "dark" : "light")") }
        }
        let runtime = Runtime()
        runtime.mount(
            NavigationView {
                Reader()
                    .modifier(Shout())
                    .environment(\.lineLimit, 2)
                    .environment(\.sizeCategory, .extraLarge)
                    .colorScheme(.dark)
                    .navigationBarTitle("Old", displayMode: .inline)
            }
            .navigationViewStyle(.stack)
        )
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(texts(runtime).contains("4 XL dark") && runtime.navigationTitle == "Old")
        #expect(ContentSizeCategory.accessibilityLarge.isAccessibilityCategory && ContentSizeCategory.small < .large)
    }

    /// The value alerts and action sheets of iOS 13 present as the current alert and dialog.
    @Test func valueAlertsAndActionSheets() {
        struct Item: Identifiable { let id: Int }
        func shown(_ view: some View) -> [String] {
            let runtime = Runtime()
            runtime.mount(view)
            runtime.layout(in: CGSize(width: 300, height: 300))
            return runtime.presentations.flatMap { $0.content.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString } }
        }
        let single = shown(Text("root").alert(isPresented: .constant(true)) { Alert(title: Text("Saved"), message: Text("All done.")) })
        #expect(single.contains("Saved") && single.contains("All done.") && single.contains("OK"))
        let pair = shown(Text("root").alert(item: .constant(Item(id: 3))) { item in
            Alert(title: Text("Delete \(item.id)?"), primaryButton: .destructive(Text("Delete")) {}, secondaryButton: .cancel())
        })
        #expect(pair.contains("Delete 3?") && pair.contains("Delete") && pair.contains("Cancel"))
        #expect(shown(Text("root").alert(item: .constant(nil as Item?)) { _ in Alert(title: Text("Never")) }).isEmpty)
        let sheet = shown(Text("root").actionSheet(isPresented: .constant(true)) {
            ActionSheet(title: Text("Share"), buttons: [.default(Text("Copy")), .cancel()])
        })
        #expect(sheet.contains("Share") && sheet.contains("Copy") && sheet.contains("Cancel"))
    }

    @Test func renamedModifiersAndTheTintStyle() {
        let runtime = Runtime()
        runtime.mount(NavigationStack {
            TextField("Name", text: .constant("")).disableAutocorrection(true).navigationTitle("Hidden").navigationBarHidden(true)
        })
        runtime.layout(in: CGSize(width: 300, height: 200))
        var environment = EnvironmentValues()
        #expect(TintShapeStyle().resolveColor(in: environment) == Color.accentColor.resolve(in: environment))
        environment._tint = .red
        let tint: TintShapeStyle = .tint
        #expect(tint.resolveColor(in: environment) == Color.red.resolve(in: environment))
    }
}
