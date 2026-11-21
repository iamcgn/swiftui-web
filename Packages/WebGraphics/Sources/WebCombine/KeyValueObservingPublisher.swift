// Combine's key-value observing publisher, `publisher(for: \.keyPath)` on an NSObject (Hipstapaper
// watches `Progress.fractionCompleted` with it). On wasm it rides on WebFoundation's
// `observe(_:options:changeHandler:)`, so it reports the changes that does: an observable
// object's sets (wasm's `Progress`) and `willChangeValue`/`didChangeValue` calls. Native
// platforms keep Foundation's.
#if os(WASI)
import WebFoundation

extension NSObject {
    /// A publisher of the value at a key path of an object, as it changes.
    public struct KeyValueObservingPublisher<Subject: NSObject, Value>: Publisher {
        public typealias Output = Value
        public typealias Failure = Never
        public let object: Subject
        public let keyPath: KeyPath<Subject, Value>
        public let options: NSKeyValueObservingOptions

        public init(object: Subject, keyPath: KeyPath<Subject, Value>, options: NSKeyValueObservingOptions) {
            self.object = object
            self.keyPath = keyPath
            self.options = options
        }

        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Value) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Never>) -> Void) -> AnyCancellable {
            let keyPath = keyPath
            // A prior report sends the old value (with `.old`); any other, the new one.
            let observation = object.observe(keyPath, options: options) { object, change in
                nonisolated(unsafe) let value = change.isPrior ? change.oldValue : (change.newValue ?? object[keyPath: keyPath])
                guard value != nil else { return }
                MainActor.assumeIsolated { receive(value!) }
            }
            return AnyCancellable { observation.invalidate() }
        }
    }
}

extension _KeyValueCodingAndObserving where Self: NSObject {
    /// Publishes the value at the key path: at once (`.initial`) and on each change (`.new`), by
    /// default.
    public func publisher<Value>(for keyPath: KeyPath<Self, Value>,
                                 options: NSKeyValueObservingOptions = [.initial, .new]) -> NSObject.KeyValueObservingPublisher<Self, Value> {
        NSObject.KeyValueObservingPublisher(object: self, keyPath: keyPath, options: options)
    }
}
#endif
