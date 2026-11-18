// A block as a method's implementation with the Objective-C runtime on wasm (decision 0023):
// `imp_implementationWithBlock`, `imp_getBlock` and `imp_removeBlock`, which the runtime SDK
// does not have. swift-dependencies adds an XCTest observer's method from a block this way
// (CriticalMaps, and every app on The Composable Architecture).
//
// The implementation is a trampoline from WebObjCBlocks' fixed pool, one for each shape of call:
// a block taking the receiver and up to five pointer, object or 32-bit integer arguments, and
// returning nothing, one of those, a 64-bit integer, a Float or a Double. Eight blocks of a shape
// can be methods at once; `imp_removeBlock` frees one's trampoline.
#if os(WASI) && canImport(ObjectiveC)
import WebObjCBlocks

/// The block values the trampolines call, by trampoline. Kept as the values the callers passed,
/// so each block lives as long as its method: the Swift runtime copies and releases a block value
/// as a block, where a reference to it as `AnyObject` would retain it as an object. The runtime
/// SDK's wasm is single-threaded.
nonisolated(unsafe) private var blockValues: [UnsafeRawPointer: Any] = [:]

/// The block object a block value is, or nil for a value of another size; WebObjCBlocks checks
/// that it is a block.
private func blockObject<Value>(_ value: Value) -> UnsafeRawPointer? {
    guard MemoryLayout<Value>.size == MemoryLayout<UnsafeRawPointer>.size else { return nil }
    return unsafeBitCast(value, to: UnsafeRawPointer?.self)
}

/// A method implementation that calls `block` with the receiver and then the method's
/// arguments (not the selector), as Apple's runtime makes one. Stops the program with the reason
/// when the block is not one, or its call has a shape the trampolines do not take.
public func imp_implementationWithBlock(_ block: Any) -> IMP {
    var reason: UnsafePointer<CChar>?
    guard let object = _openExistential(block, do: blockObject), let imp = _webIMPWithBlock(object, &reason) else {
        fatalError("imp_implementationWithBlock: \(reason.map { String(cString: $0) } ?? "the value is not a block")")
    }
    blockValues[UnsafeRawPointer(imp)] = block
    return unsafeBitCast(imp, to: IMP.self)
}

/// The block an implementation from `imp_implementationWithBlock` calls, or nil.
public func imp_getBlock(_ anImp: IMP) -> Any? {
    blockValues[unsafeBitCast(anImp, to: UnsafeRawPointer.self)]
}

/// Releases the block an implementation from `imp_implementationWithBlock` calls, and frees its
/// trampoline for another block: true when `anImp` was such an implementation. A method still
/// holding it must not be called after.
public func imp_removeBlock(_ anImp: IMP) -> Bool {
    let trampoline = unsafeBitCast(anImp, to: UnsafeRawPointer.self)
    guard _webRemoveIMPBlock(trampoline) != 0 else { return false }
    blockValues[trampoline] = nil
    return true
}
#endif
