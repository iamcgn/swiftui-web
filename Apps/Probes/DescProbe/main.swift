// Scratch probe (not for merge): which `description` declarations the objc SDK sees.
import Foundation

final class One: NSObject {
    override var description: String { "One" }
    var read: Any { description }
}

class Base: NSObject {
    override var description: String { "Base" }
}
final class Two: Base {
    override var description: String { "Two" }
}

protocol Shown {}
enum Outer<T> {}
extension Outer {
    final class Inner<D>: NSObject, CustomReflectable, CustomPlaygroundDisplayConvertible {
        override var description: String { return "Timer" }
        var customMirror: Mirror { Mirror(self, children: []) }
        var playgroundDescription: Any { return description }
    }
}

final class Plain: NSObject {}

let one = One()
print(one.description, one.read)
print(Two().description)
let n: NSObject = Plain()
print(n.description, String(describing: n))
let p = Plain()
print(p.description)
print(Outer<Int>.Inner<Int>().playgroundDescription)
