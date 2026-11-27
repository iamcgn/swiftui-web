// The value accessors that Foundation's `NSNumber` and `NSString` both answer as Objective-C
// messages, for wasm with the Objective-C runtime: a member called on `AnyObject` is found only
// among `@objc` declarations, and an `@objc` protocol's requirements are, with the members that
// satisfy them made `@objc` too. So `(delay as AnyObject).doubleValue` compiles and reads a
// number or a numeric string, as on iOS (EmojiText's animated-image frame delay). Only the
// accessors whose type is the same on both classes are here, so a lookup is never ambiguous.
#if os(WASI) && canImport(ObjectiveC)

/// What `NSNumber` and `NSString` both answer: the value as a double, a float and a truth.
@objc public protocol _WebNumericValues {
    var doubleValue: Double { get }
    var floatValue: Float { get }
    var boolValue: Bool { get }
}

extension NSNumber: _WebNumericValues {}
extension _WebNSString: _WebNumericValues {}

#endif
