// The root of UIKit's value classes (colours, fonts, images and Bézier paths). UIKit's are
// NSObjects, so with an Objective-C runtime (decision 0023) these are too: an `@objc` method or
// protocol can take or return one, as CVCalendar's appearance delegate returns colours and
// fonts, and they compare and hash by `isEqual(_:)` and `hash`, as in Objective-C.
import WebFoundation   // Foundation everywhere, and the Objective-C runtime where there is one

#if canImport(ObjectiveC)
public typealias UIObjectBase = NSObject
#else
/// The root of UIKit's value classes without an Objective-C runtime: each class compares and
/// hashes as Swift's `Hashable` says.
open class UIObjectBase {
    public init() {}
}
#endif
