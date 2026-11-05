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
