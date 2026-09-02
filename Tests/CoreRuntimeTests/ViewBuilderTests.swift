// Phase 1 step 1: the View / ViewBuilder API skeleton type-checks the documented builder forms.
import Testing
import SwiftUI

private struct Leaf: View {
    var id: Int
    var body: some View { EmptyView() }
}

private struct Other: View {
    var body: some View { EmptyView() }
}

private struct Flags {
    var a = true
    var maybe: Int? = 7
}

private struct BuilderView: View {
    var flags = Flags()

    // if/else, optional, `if let`, Group, switch, nested builder.
    @ViewBuilder var body: some View {
        Leaf(id: 1)
        if flags.a {
            Leaf(id: 2)
        } else {
            Other()
        }
        if flags.a {
            Leaf(id: 3)
        }
        if let n = flags.maybe {
            Leaf(id: n)
        }
        Group {
            Leaf(id: 4)
            Leaf(id: 5)
        }
        switch flags.maybe {
        case .some(let n): Leaf(id: n)
        case .none: EmptyView()
        }
        if #available(macOS 14, *) {
            Leaf(id: 6)
        }
    }
}

private struct TwelveChildren: View {
    var body: some View {
        Leaf(id: 1); Leaf(id: 2); Leaf(id: 3); Leaf(id: 4)
        Leaf(id: 5); Leaf(id: 6); Leaf(id: 7); Leaf(id: 8)
        Leaf(id: 9); Leaf(id: 10); Leaf(id: 11); Leaf(id: 12)
    }
}

private struct Uppercased: ViewModifier {
    func body(content: Content) -> some View { content }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = "light"
}

extension EnvironmentValues {
    fileprivate var theme: String {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct ThemedView: View {
    @Environment(\.theme) var theme
    var body: some View { EmptyView() }
}

private struct SpeedKey: TransactionKey {
    static let defaultValue = 1.0
}

private func sameType(_ a: Any.Type, _ b: Any.Type) -> Bool { a == b }

private typealias BuilderBody = TupleView<(
    Leaf,
    _ConditionalContent<Leaf, Other>,
    Leaf?,
    Leaf?,
    Group<TupleView<(Leaf, Leaf)>>,
    _ConditionalContent<Leaf, EmptyView>,
    AnyView?
)>

@Suite @MainActor struct ViewBuilderTests {
    @Test func builderProducesDocumentedTypes() throws {
        // (Leaf, if/else, if, if-let, Group, switch, #available)
        let body = try #require(BuilderView().body as? BuilderBody)
        let value = body.value
        #expect(value.0.id == 1)
        if case .trueContent(let leaf) = value.1.storage { #expect(leaf.id == 2) } else { Issue.record("expected true branch") }
        #expect(value.2?.id == 3)
        #expect(value.3?.id == 7)
        #expect(value.4.content.value.0.id == 4)
        #expect(value.4.content.value.1.id == 5)
        if case .trueContent(let leaf) = value.5.storage { #expect(leaf.id == 7) } else { Issue.record("expected .some branch") }
        #expect(sameType(try #require(value.6).viewType, Leaf.self))

        let falseBody = try #require(BuilderView(flags: Flags(a: false, maybe: nil)).body as? BuilderBody)
        if case .falseContent = falseBody.value.1.storage {} else { Issue.record("expected false branch") }
        #expect(falseBody.value.2 == nil)
        #expect(falseBody.value.3 == nil)
        if case .falseContent = falseBody.value.5.storage {} else { Issue.record("expected .none branch") }
    }

    @Test func twelveChildrenTypeCheck() throws {
        typealias Twelve = TupleView<(Leaf, Leaf, Leaf, Leaf, Leaf, Leaf, Leaf, Leaf, Leaf, Leaf, Leaf, Leaf)>
        let body = try #require(TwelveChildren().body as? Twelve)
        #expect(body.value.11.id == 12)
    }

    @Test func emptyAndSingleBlocks() {
        @ViewBuilder func empty() -> some View {}
        @ViewBuilder func single() -> some View { Leaf(id: 9) }
        #expect(sameType(type(of: empty()), EmptyView.self))
        #expect(sameType(type(of: single()), Leaf.self))
    }

    @Test func anyViewErasesAndReportsDynamicType() throws {
        let any = AnyView(Leaf(id: 3))
        #expect(sameType(any.viewType, Leaf.self))
        // Wrapping an AnyView does not nest.
        #expect(sameType(AnyView(any).viewType, Leaf.self))
        #expect(sameType(AnyView(erasing: Other()).viewType, Other.self))
        let fromValue = try #require(AnyView(_fromValue: Other()))
        #expect(sameType(fromValue.viewType, Other.self))
        #expect(AnyView(_fromValue: 42) == nil)
        let existential: any View = Leaf(id: 5)
        #expect(sameType(AnyView(existential).viewType, Leaf.self))
    }

    @Test func modifiersCompose() {
        let modified = Leaf(id: 1).modifier(Uppercased()).modifier(EmptyModifier.identity)
        #expect(modified.content.content.id == 1)
        let concatenated = Uppercased().concat(EmptyModifier())
        let applied = Leaf(id: 2).modifier(concatenated)
        #expect(applied.content.id == 2)
        #expect(sameType(type(of: applied), ModifiedContent<Leaf, ModifiedContent<Uppercased, EmptyModifier>>.self))
    }

    @Test func environmentValuesAndProperty() throws {
        var values = EnvironmentValues()
        #expect(values.theme == "light")
        values.theme = "dark"
        #expect(values.theme == "dark")
        #expect(values[ThemeKey.self] == "dark")

        #expect(ThemedView().theme == "light")     // default before the runtime resolves it
        var property = Environment(\.theme)
        #expect(property.wrappedValue == "light")
        property.resolve(in: values)
        #expect(property.wrappedValue == "dark")

        // `.environment` produces a primitive environment-writing modifier.
        let view = try #require(
            ThemedView().environment(\.theme, "high-contrast")
                as? ModifiedContent<ThemedView, _EnvironmentKeyWritingModifier<String>>)
        var resolved = EnvironmentValues()
        view.modifier.modifyEnvironment(&resolved)
        #expect(resolved.theme == "high-contrast")

        let transformed = try #require(
            ThemedView().transformEnvironment(\.theme) { $0 += "!" }
                as? ModifiedContent<ThemedView, _EnvironmentKeyTransformModifier<String>>)
        transformed.modifier.modifyEnvironment(&resolved)
        #expect(resolved.theme == "high-contrast!")
    }

    @Test func transactionStub() {
        var t = Transaction()
        #expect(!t.disablesAnimations)
        #expect(t[SpeedKey.self] == 1.0)
        t[SpeedKey.self] = 2.5
        t.disablesAnimations = true
        #expect(Transaction._current == nil)
        let seen = withTransaction(t) { Transaction._current?[SpeedKey.self] }
        #expect(seen == 2.5)
        #expect(Transaction._current == nil)
    }
}
