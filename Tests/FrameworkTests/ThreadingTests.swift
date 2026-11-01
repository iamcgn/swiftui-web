// Foundation's locks, cache, thread sleep, clock constants and `String.appending` as the wasm
// stand-ins give them (Packages/WebGraphics/Sources/WebFoundation/Threading.swift): the same
// answers as Foundation's own on macOS and Linux.
import Testing
import WebFoundation

private struct LookupFailed: CustomNSError {}

@Suite struct ThreadingTests {
    @Test func locks() {
        let lock = NSLock()
        #expect(lock.withLock { 42 } == 42)
        #expect(lock.try())
        #expect(!lock.try())
        lock.unlock()
        #expect(lock.try())
        lock.unlock()

        let recursive = NSRecursiveLock()
        recursive.lock()
        #expect(recursive.try())
        recursive.unlock()
        recursive.unlock()
        #expect(recursive.withLock { "inside" } == "inside")
    }

    @Test func cache() {
        let cache = NSCache<NSString, NSString>()
        let key: NSString = "kingfisher"
        #expect(cache.object(forKey: key) == nil)
        cache.setObject("first", forKey: key)
        #expect(cache.object(forKey: "kingfisher" as NSString) == "first")
        cache.setObject("second", forKey: key, cost: 10)
        #expect(cache.object(forKey: key) == "second")
        cache.removeObject(forKey: key)
        #expect(cache.object(forKey: key) == nil)
        cache.setObject("a", forKey: "a")
        cache.setObject("b", forKey: "b")
        cache.removeAllObjects()
        #expect(cache.object(forKey: "a") == nil)
        #expect(cache.object(forKey: "b") == nil)
        cache.name = "images"
        #expect(cache.name == "images")
    }

    #if os(WASI)
    @Test func cacheLimitsEvictTheOldest() {
        // Apple's cache evicts when it chooses; the stand-in evicts the oldest at once.
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 2
        cache.setObject("1", forKey: "one")
        cache.setObject("2", forKey: "two")
        cache.setObject("3", forKey: "three")
        #expect(cache.object(forKey: "one") == nil)
        #expect(cache.object(forKey: "three") == "3")
        #expect(Thread.isMainThread)
        #expect(Thread.current.isMainThread)
    }
    #endif

    @Test func sleepAndClocks() {
        let start = Date()
        Thread.sleep(forTimeInterval: 0.02)
        #expect(Date().timeIntervalSince(start) >= 0.02)
        #expect(NSEC_PER_SEC == 1_000_000_000)
        #expect(NSEC_PER_MSEC == 1_000_000)
        #expect(USEC_PER_SEC == 1_000_000)
        #expect(abs(CFAbsoluteTimeGetCurrent() - Date().timeIntervalSinceReferenceDate) < 1)
        let interval: CFTimeInterval = 1.5
        #expect(interval == 1.5)
    }

    @Test func appendingAndErrorNames() {
        #expect("Image".appending("Cache") == "ImageCache")
        #expect("path"[...].appending("/file") == "path/file")
        #expect(LookupFailed.errorDomain.hasSuffix("LookupFailed"))
        #expect(LookupFailed().errorCode == 1)
        #expect(LookupFailed().errorUserInfo.isEmpty)
    }
}
