// The same shape over local stand-ins whose ObservedObject is main-actor isolated, as Apple's is.
public protocol ObservableObject: AnyObject {}

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

@MainActor @preconcurrency @propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject> {
    @dynamicMemberLookup
    public struct Wrapper {
        let root: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            let root = root
            return Binding(get: { root[keyPath: keyPath] }, set: { root[keyPath: keyPath] = $0 })
        }
    }
    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public var projectedValue: Wrapper { Wrapper(root: wrappedValue) }
}

@dynamicMemberLookup @propertyWrapper
public struct PBindable<Value: AnyObject> {
    @ObservedObject fileprivate var observer: Observer<Value>
    public var wrappedValue: Value { observer.object }
    public init(wrappedValue: Value) { observer = Observer(wrappedValue) }
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        $observer[dynamicMember: (\Observer<Value>.object).appending(path: keyPath)]
    }
}

final class Observer<Object: AnyObject>: ObservableObject {
    var object: Object
    init(_ object: Object) { self.object = object }
}
