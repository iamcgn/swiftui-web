// Names Apple's Foundation brings with the Objective-C runtime, for the stock wasm SDK, where
// there is none: `autoreleasepool` (Nuke and Kingfisher wrap their image decoding in it),
// `NSClassFromString` (RevenueCat looks up the ad-support classes by name and does without
// them when they are missing) and the `NSInteger` and `NSUInteger` aliases (Kingfisher's display
// link protocol). With the Objective-C runtime SDK the runtime's own declarations are in scope
// instead (WebFoundation re-exports `ObjectiveC`, decision 0023).
#if os(WASI) && !canImport(ObjectiveC)

/// Runs `body` and returns what it returns. Without the runtime nothing is autoreleased, so
/// there is no pool to drain: Swift releases each object when its last reference goes.
public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}

/// The class Swift knows by `aClassName`, as `NSStringFromClass` names it ("Module.Class"),
/// or nil. Without the runtime only Swift's own type metadata can be searched, so the name of
/// an Objective-C class, which has none here, finds nothing, as on a device without the
/// framework that declares it.
public func NSClassFromString(_ aClassName: String) -> AnyClass? {
    guard !aClassName.isEmpty else { return nil }
    return _typeByName(aClassName) as? AnyClass
}

/// Objective-C's integer types, as Swift imports them.
public typealias NSInteger = Int
public typealias NSUInteger = UInt

public let NSIntegerMax: Int = .max
public let NSIntegerMin: Int = .min
public let NSUIntegerMax: UInt = .max

#endif
