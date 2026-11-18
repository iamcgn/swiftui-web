// `ObservedObject.Wrapper` is a type of its own, as Apple's is, so a library extends it (the
// Composable Architecture's store bindings), and `$object` from each wrapper is one.
import Testing
import SwiftUI

final class WrapperModel: ObservableObject {
    @Published var count = 1
}

extension ObservedObject.Wrapper where ObjectType == WrapperModel {
    /// A binding a library adds to every `$model`.
    var doubled: Binding<Int> {
        let count = self.count
        return Binding(get: { count.wrappedValue * 2 }, set: { count.wrappedValue = $0 / 2 })
    }
}

@Suite @MainActor struct ObservedObjectWrapperTests {
    @Test func anExtensionOfTheWrapperReachesTheObject() {
        let model = WrapperModel()
        let wrapper = ObservedObject(wrappedValue: model).projectedValue
        #expect(wrapper.doubled.wrappedValue == 2)
        wrapper.doubled.wrappedValue = 10
        #expect(model.count == 5)
    }

    @Test func stateAndEnvironmentObjectsProjectTheSameWrapper() {
        let fromState: ObservedObject<WrapperModel>.Wrapper = StateObject(wrappedValue: WrapperModel()).projectedValue
        #expect(fromState.doubled.wrappedValue == 2)
        // An environment object's projection is the same type (read without an ancestor's object
        // it would stop, so only its type is checked).
        let fromEnvironment: (EnvironmentObject<WrapperModel>) -> ObservedObject<WrapperModel>.Wrapper = { $0.projectedValue }
        _ = fromEnvironment
    }
}
