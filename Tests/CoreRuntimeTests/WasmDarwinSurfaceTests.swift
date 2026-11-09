// The Darwin pieces packages reach for through Foundation on wasm: the loader finds nothing,
// dyld lists no images, and strings, dates and UUIDs pass as `CVarArg` into the formatters.
#if os(WASI)
import Testing
import WebFoundation

@Suite struct WasmDarwinSurfaceTests {
    @Test func theLoaderFindsNothing() {
        let handle = dlopen(nil, RTLD_NOW)
        #expect(handle == nil)
        #expect(dlsym(handle, "XCTFail") == nil)
        #expect(dlerror() == nil)
        #expect(_dyld_image_count() == 0)
        #expect(_dyld_get_image_name(0) == nil)
        #expect(Thread.callStackReturnAddresses.isEmpty)
    }

    @Test func valueTypesPassAsCVarArgs() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let id = UUID()
        let arguments: [CVarArg] = ["name", date, id]
        #expect(arguments[0] as? String == "name")
        #expect(arguments[1] as? Date == date)
        #expect(arguments[2] as? UUID == id)
        #expect(String(format: "%@ and %@", arguments: ["a" as CVarArg, "b" as CVarArg]) == "a and b")
    }
}
#endif

// Mach-O's structures, as swift-perception walks an image's segments (its 32-bit path, which
// wasm32 takes): the layout matches Darwin's, so this runs against Darwin on macOS too.
#if os(WASI) || canImport(Darwin)
import Testing
import WebFoundation
#if canImport(Darwin)
import Darwin
import Foundation
#endif

@Suite struct MachOLayoutTests {
    @Test func structuresHaveDarwinsLayout() {
        #expect(MemoryLayout<mach_header>.size == 28)
        #expect(MemoryLayout<load_command>.size == 8)
        #expect(MemoryLayout<segment_command>.size == 56)
        #expect(LC_SEGMENT == 0x1)
    }

    @Test func segmentsWalkFromTheHeader() {
        var header = mach_header()
        header.ncmds = 2
        var text = segment_command()
        text.cmd = UInt32(LC_SEGMENT)
        text.cmdsize = UInt32(MemoryLayout<segment_command>.size)
        text.vmaddr = 0x1000
        text.vmsize = 0x200
        var other = load_command()
        other.cmd = 0x2
        other.cmdsize = UInt32(MemoryLayout<load_command>.size)
        var image: [UInt8] = []
        withUnsafeBytes(of: header) { image += $0 }
        withUnsafeBytes(of: text) { image += $0 }
        withUnsafeBytes(of: other) { image += $0 }

        var segments: [Range<Int>] = []
        image.withUnsafeBytes { buffer in
            let start = buffer.baseAddress!
            let walked = start.loadUnaligned(as: mach_header.self)
            var command = start.advanced(by: MemoryLayout<mach_header>.size)
            for _ in 0..<walked.ncmds {
                let cmd = command.loadUnaligned(as: load_command.self)
                if cmd.cmd == LC_SEGMENT {
                    let segment = command.loadUnaligned(as: segment_command.self)
                    segments.append(Int(segment.vmaddr)..<Int(segment.vmaddr + segment.vmsize))
                }
                command = command.advanced(by: Int(cmd.cmdsize))
            }
        }
        #expect(segments == [0x1000..<0x1200])
        #if os(WASI)
        #expect(_dyld_get_image_vmaddr_slide(0) == 0)
        #endif
    }

    @Test func returnAddressesReadAsPointers() {
        let number = NSNumber(value: UInt(0x4000))
        #expect(UInt(bitPattern: number.pointerValue) == 0x4000)
    }
}
#endif
