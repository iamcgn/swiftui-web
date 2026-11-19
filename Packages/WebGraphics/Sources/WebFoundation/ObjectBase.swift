// The superclass of the Foundation classes this module declares that are `NSObject`s on Apple's
// platforms (NSNumber, UserDefaults, NotificationCenter, Bundle, FileManager, URLSession, Timer,
// RunLoop). With an Objective-C runtime (decision 0023) it is `NSObject`, so `@objc` members can
// take and return them (RevenueCat's `with(userDefaults:)`, a `@objc func tick(_ timer: Timer)`
// a timer's selector names) and they answer `responds(to:)`, `perform` and key-value coding as
// any object does. Without the runtime it is an empty class, so the stock wasm build keeps them
// as plain classes and pays for nothing.
#if os(WASI)
#if canImport(ObjectiveC)
public typealias _WebObjectBase = NSObject
#else
open class _WebObjectBase {
    public init() {}

    // Sending a message by selector, as `NSObject` answers without the runtime: no method is
    // registered under a selector, so code that checks first takes its branch for a missing
    // one (swift-sharing asks a `UserDefaults` whether it responds to `_identifier`).
    open func responds(to aSelector: Selector!) -> Bool { false }
    open func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    open func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
}
#endif
#endif
