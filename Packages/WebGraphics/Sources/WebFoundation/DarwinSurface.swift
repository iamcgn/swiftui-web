// What packages reach for through Apple's Foundation, which re-exports Darwin, when they build
// for a platform with Objective-C and `os` (as the objc SDK is): the dynamic loader's `dlopen`
// family, dyld's image list and the Mach-O structures that walk an image, and strings, dates
// and UUIDs as `CVarArg` (Apple bridges them to their NSObject classes). A page loads no
// libraries, so the loader and the image list find nothing; a `CVarArg` value travels as
// itself, and WebFoundation's formatters read it from there.
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

/// The header of a loaded image, laid out as Mach-O's 32-bit header. No image is ever loaded,
/// so these exist for code that walks an image's load commands behind `_dyld_image_count()`.
/// wasm32 is a 32-bit target, so code that picks `mach_header_64` on 64-bit targets picks
/// these; the 64-bit forms are left out.
public struct mach_header {
    public var magic: UInt32 = 0
    public var cputype: Int32 = 0
    public var cpusubtype: Int32 = 0
    public var filetype: UInt32 = 0
    public var ncmds: UInt32 = 0
    public var sizeofcmds: UInt32 = 0
    public var flags: UInt32 = 0
    public init() {}
}

/// The start every load command shares: its kind and its size in bytes.
public struct load_command {
    public var cmd: UInt32 = 0
    public var cmdsize: UInt32 = 0
    public init() {}
}

/// A segment load command (32-bit addresses).
public struct segment_command {
    public var cmd: UInt32 = 0
    public var cmdsize: UInt32 = 0
    public var segname: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                         CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    public var vmaddr: UInt32 = 0
    public var vmsize: UInt32 = 0
    public var fileoff: UInt32 = 0
    public var filesize: UInt32 = 0
    public var maxprot: Int32 = 0
    public var initprot: Int32 = 0
    public var nsects: UInt32 = 0
    public var flags: UInt32 = 0
    public init() {}
}

public let LC_SEGMENT: Int32 = 0x1

/// The number of loaded images: the page's module is not a Mach-O image, so none.
public func _dyld_image_count() -> UInt32 { 0 }
public func _dyld_get_image_name(_ imageIndex: UInt32) -> UnsafePointer<CChar>? { nil }
public func _dyld_get_image_header(_ imageIndex: UInt32) -> UnsafePointer<mach_header>? { nil }
/// How far an image was moved from its preferred address: there is no image, so no slide.
public func _dyld_get_image_vmaddr_slide(_ imageIndex: UInt32) -> Int { 0 }

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
