import SwiftUI

/// Shaped like swift-perception's back-ported Bindable: a struct holding an @ObservedObject.
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
