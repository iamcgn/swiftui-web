// Decision 0021: `import Foundation` on wasm is Packages/Shadows' module, so an app file that
// imports Foundation beside SwiftUI names one `URL` and one `Data`, reaches libm, `@Observable`
// and `DispatchQueue`, and SwiftPM's `Bundle.module` accessor compiles.
#if os(WASI)
import Testing
import Foundation
import SwiftUI

@Suite struct ShadowFoundationTests {
    @Test func foundationIsWebFoundationWithTheReExports() {
        let url = URL(string: "https://example.com/a")!
        let data = Data("hi".utf8)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        #expect(url.path == "/a" && data.count == 2 && formatter.string(from: 3) == "3")
        #expect(sqrt(16.0) == 4 && log2(8.0) == 3 && pow(2.0, 3.0) == 8)
        #expect(Calendar.current.component(.year, from: Date()) >= 2026)
        #expect(Bundle(path: "/build/App_Target.resources") != nil)
        #expect(Color("accent", bundle: .main) == Color("accent") && Image("logo", bundle: .main) == Image("logo"))
    }

    // The Node test runner cannot wait on the event loop ("async io not supported"), so the
    // queued forms are covered by the apps' probes; the in-place forms here.
    @Test func dispatchQueuesRunInPlace() {
        final class Log: @unchecked Sendable { var order: [String] = [] }
        let log = Log()
        DispatchQueue.main.sync { log.order.append("sync") }
        let value = DispatchQueue.global(qos: .background).sync { 7 }
        let item = DispatchWorkItem { log.order.append("cancelled") }
        item.cancel()
        DispatchQueue.main.sync(execute: item)
        DispatchQueue(label: "work").sync(execute: DispatchWorkItem { log.order.append("item") })
        #expect(log.order == ["sync", "item"] && value == 7 && item.isCancelled)
        let now = DispatchTime.now()
        #expect(now < now + 1 && now < now + .milliseconds(5) && (now + .seconds(2))._delay > 1.9)
        #expect((DispatchWallTime.now() + 1)._delay > 0.9 && DispatchTimeInterval.milliseconds(1500)._seconds == 1.5)
    }
}
#endif
