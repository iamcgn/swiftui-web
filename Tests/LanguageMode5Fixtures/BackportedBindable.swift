// Built in the Swift 5 language mode, as swift-perception is: a property wrapper type shaped like
// its back-ported `Bindable`, a struct that holds an `@ObservedObject`. In this mode the struct
// takes the main-actor isolation of `ObservedObject`, as it does over Apple's SwiftUI.
import SwiftUI

@dynamicMemberLookup
@propertyWrapper
public struct BackportedBindable<Value: AnyObject> {
    @ObservedObject fileprivate var observer: Observer<Value>

    public init(wrappedValue: Value) { observer = Observer(wrappedValue) }

    public var wrappedValue: Value { observer.object }

    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        $observer[dynamicMember: (\Observer<Value>.object).appending(path: keyPath)]
    }
}

final class Observer<Object: AnyObject>: ObservableObject {
    var object: Object
    init(_ object: Object) { self.object = object }
}
