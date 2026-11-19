import SwiftUI
import PercOurs

@MainActor
public final class Store<State, Action> {
    var state: State
    init(_ state: State) { self.state = state }
}

extension Store {
    public subscript<ChildState, ChildAction>(
        state state: KeyPath<State, ChildState?>,
        action action: KeyPath<Action, ChildAction?>,
        isInViewBody isInViewBody: Bool = false
    ) -> Store<ChildState, ChildAction>? {
        get { nil }
        set {}
    }
}

extension PBindable {
    public func scope<State, Action, ChildState, ChildAction>(
        state: KeyPath<State, ChildState?>,
        action: KeyPath<Action, ChildAction?>
    ) -> Binding<Store<ChildState, ChildAction>?> where Value == Store<State, Action> {
        self[state: state, action: action]
    }
}
