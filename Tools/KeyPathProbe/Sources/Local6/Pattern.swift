// A stand-in Binding shaped like this repo's, to tell the Binding's shape from the module.
@propertyWrapper @dynamicMemberLookup
public struct Binding<Value> {
    let getter: () -> Value
    let setter: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { getter = get; setter = set }
    public var wrappedValue: Value { get { getter() } nonmutating set { setter(newValue) } }
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(get: { self.wrappedValue[keyPath: keyPath] },
                         set: { var v = self.getter(); v[keyPath: keyPath] = $0; self.setter(v) })
    }
}

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
