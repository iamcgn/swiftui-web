import SwiftUI

@MainActor @dynamicMemberLookup
public final class Store<State, Action> {
    var state: State
    init(_ state: State) { self.state = state }
    public subscript<T>(dynamicMember keyPath: KeyPath<State, T>) -> T { state[keyPath: keyPath] }
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

extension Binding {
    @preconcurrency @MainActor
    public func scope<State, Action, ChildState, ChildAction>(
        state: KeyPath<State, ChildState?>,
        action: KeyPath<Action, ChildAction?>
    ) -> Binding<Store<ChildState, ChildAction>?> where Value == Store<State, Action> {
        self[state: state, action: action]
    }

    @MainActor
    public func scopePlainMainActor<State, Action, ChildState, ChildAction>(
        state: KeyPath<State, ChildState?>,
        action: KeyPath<Action, ChildAction?>
    ) -> Binding<Store<ChildState, ChildAction>?> where Value == Store<State, Action> {
        self[state: state, action: action]
    }

    @MainActor
    public func scopeExplicitKeyPath<State, Action, ChildState, ChildAction>(
        state: KeyPath<State, ChildState?>,
        action: KeyPath<Action, ChildAction?>
    ) -> Binding<Store<ChildState, ChildAction>?> where Value == Store<State, Action> {
        self[dynamicMember: \Store<State, Action>.[state: state, action: action]]
    }
}
