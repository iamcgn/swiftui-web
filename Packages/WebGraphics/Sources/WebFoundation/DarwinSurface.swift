// What packages reach for through Apple's Foundation, which re-exports Darwin, when they build
// for a platform with Objective-C and `os` (as the objc SDK is): the dynamic loader's `dlopen`
// family and dyld's image list, and strings, dates and UUIDs as `CVarArg` (Apple bridges them
// to their NSObject classes). A page loads no libraries, so the loader finds nothing; a
// `CVarArg` value travels as itself, and WebFoundation's formatters read it from there.
#if os(WASI)

// MARK: - Dynamic loading

public let RTLD_LAZY: Int32 = 0x1
public let RTLD_NOW: Int32 = 0x2
public let RTLD_LOCAL: Int32 = 0x4
public let RTLD_GLOBAL: Int32 = 0x8

/// Opens a dynamic library: a page has none to open, so nil.
public func dlopen(_ path: UnsafePointer<CChar>?, _ mode: Int32) -> UnsafeMutableRawPointer? { nil }
/// Looks up a symbol: none can be found, so nil.
public func dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer? { nil }
public func dlclose(_ handle: UnsafeMutableRawPointer) -> Int32 { 0 }
/// The last loader error: none is recorded, so nil.
public func dlerror() -> UnsafeMutablePointer<CChar>? { nil }

// MARK: - dyld's image list

/// The header of a loaded image (Mach-O's, opaque here).
public struct mach_header {}

/// The number of loaded images: the page's module is not a Mach-O image, so none.
public func _dyld_image_count() -> UInt32 { 0 }
public func _dyld_get_image_name(_ imageIndex: UInt32) -> UnsafePointer<CChar>? { nil }
public func _dyld_get_image_header(_ imageIndex: UInt32) -> UnsafePointer<mach_header>? { nil }

// MARK: - CVarArg

extension String: @retroactive CVarArg {
    public var _cVarArgEncoding: [Int] { [0] }
}

extension Date: @retroactive CVarArg {
    public var _cVarArgEncoding: [Int] { [0] }
}

extension UUID: @retroactive CVarArg {
    public var _cVarArgEncoding: [Int] { [0] }
}
#endif
