// A library's extension of a Swift 5 property wrapper type that holds an `@ObservedObject`
// (the Composable Architecture's `Perception.Bindable.scope`) forms key paths to main-actor
// members of a main-actor class; that needs the type to be main-actor isolated, which it takes
// from `ObservedObject` as over Apple's SwiftUI.
import Testing
import SwiftUI
import LanguageMode5Fixtures

@MainActor
final class IsolatedCounterStore {
    var count = 0
    var children: [String: Int] = [:]

    subscript(child name: String, offset offset: Int = 0) -> Int {
        get { (children[name] ?? 0) + offset }
        set { children[name] = newValue - offset }
    }
}

extension BackportedBindable where Value == IsolatedCounterStore {
    /// No isolation written here: it comes from the wrapper type.
    func child(_ name: String) -> Binding<Int> { self[child: name] }
}

@Suite @MainActor struct BackportedBindableIsolationTests {
    @Test func anExtensionReachesMainActorSubscripts() {
        let store = IsolatedCounterStore()
        let bindable = BackportedBindable(wrappedValue: store)
        let binding = bindable.child("a")
        binding.wrappedValue = 3
        #expect(store.children["a"] == 3)
        #expect(bindable.count.wrappedValue == 0)
    }
}
