// iOS search fixtures (`ios/search/`): `searchable` in a navigation stack, at rest, presented
// with suggestions and scopes, and with tokens, captured as the whole iPhone window on the
// simulator (decision 0015) and reproduced by the runtime's iOS profile
// (Docs/elements/Toolbar.md, "iOS").
import SwiftUI
import FixtureKit

@Observable
public final class IOSSearchModel {
    public var query = ""
    public var presented = false
    public var scope = 0
    public init() {}
}

public struct SearchToken: Identifiable, Hashable {
    public let name: String
    public var id: String { name }
    public init(_ name: String) { self.name = name }
}

private let fruit = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]

private struct FruitList: View {
    let query: String
    var shown: [String] { query.isEmpty ? fruit : fruit.filter { $0.lowercased().contains(query.lowercased()) } }
    var body: some View {
        List(shown, id: \.self) { name in Text(name).probe("row-\(name)") }
            .navigationTitle("Fruit")
            .probe("list")
    }
}

public enum IOSSearchFixtures {
    private static let phone = CGSize(width: 320, height: 480)

    /// The field at rest under a large title.
    public static let basic = Fixture("ios/search/basic", size: phone) {
        NavigationStack {
            FruitList(query: "")
                .searchable(text: .constant(""), prompt: "Find fruit")
        }
        .probe("nav")
    }.platform(.iOS).capturesWindow()

    /// Presenting the search shows the suggestions and the scope bar; typing filters them.
    public static let active = Fixture(
        "ios/search/active", size: phone,
        model: { IOSSearchModel() },
        steps: [FixtureStep("present") { $0.presented = true }, FixtureStep("typed") { $0.query = "an" }]
    ) { model in
        NavigationStack {
            FruitList(query: model.query)
                .searchable(text: Binding(get: { model.query }, set: { model.query = $0 }),
                            isPresented: Binding(get: { model.presented }, set: { model.presented = $0 }),
                            prompt: "Find fruit")
                .searchScopes(Binding(get: { model.scope }, set: { model.scope = $0 }), activation: .onSearchPresentation) {
                    Text("All").tag(0)
                    Text("Fresh").tag(1)
                }
                .searchSuggestions {
                    ForEach(fruit.filter { model.query.isEmpty || $0.lowercased().contains(model.query.lowercased()) }, id: \.self) { name in
                        Text(name).searchCompletion(name).probe("suggest-\(name)")
                    }
                }
        }
        .probe("nav")
    }.platform(.iOS).capturesWindow()

    /// Tokens in the field next to the text.
    public static let tokens = Fixture("ios/search/tokens", size: phone) {
        NavigationStack {
            FruitList(query: "")
                .searchable(text: .constant("ch"), tokens: .constant([SearchToken("Fresh"), SearchToken("Red")]), prompt: "Find fruit") { token in
                    Text(token.name)
                }
        }
        .probe("nav")
    }.platform(.iOS).capturesWindow()

    public static let all: [Fixture] = [basic, active, tokens]
}
