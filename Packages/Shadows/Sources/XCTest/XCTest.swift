// `import XCTest` in an app's own code on wasm (decision 0021). The wasm SDK's XCTest is built
// against the SDK's Foundation, so beside this project's `Foundation` its module can't be read
// (the compiler stops on `_BridgedStoredNSError`). Point-Free's libraries import it outside
// tests: xctest-dynamic-overlay before 1.0 re-exports `XCTFail` from it, and swift-dependencies
// adds a test observer through `XCTestObservationCenter` on WASI. An app in a page runs no test
// case, so `XCTFail` reports its message on the console, as the overlay does outside a test,
// and an observer is kept but never called.
#if os(WASI)

/// A test or a group of tests. A page runs none, so a test here has a name and nothing to run.
open class XCTest {
    public init() {}
    /// The test's name: its class's, as XCTest names a case before it picks a method.
    open var name: String { String(describing: type(of: self)) }
    /// How many test cases it holds.
    open var testCaseCount: Int { 0 }
}

/// A test case, the class a test observer is handed.
open class XCTestCase: XCTest {
    public override init() { super.init() }
    open override var testCaseCount: Int { 1 }
}

/// What a test observer hears about. Each event has a default that does nothing, so an observer
/// implements the ones it wants.
public protocol XCTestObservation: AnyObject {
    func testCaseWillStart(_ testCase: XCTestCase)
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int)
    func testCaseDidFinish(_ testCase: XCTestCase)
}

extension XCTestObservation {
    public func testCaseWillStart(_ testCase: XCTestCase) {}
    public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {}
    public func testCaseDidFinish(_ testCase: XCTestCase) {}
}

/// The observers of the test run. A page starts no test case, so it never calls them.
open class XCTestObservationCenter: @unchecked Sendable {
    /// The one center, as XCTest has.
    public static let shared = XCTestObservationCenter()

    private var observers: [any XCTestObservation] = []

    public init() {}

    open func addTestObserver(_ testObserver: any XCTestObservation) {
        guard !observers.contains(where: { $0 === testObserver }) else { return }
        observers.append(testObserver)
    }

    open func removeTestObserver(_ testObserver: any XCTestObservation) {
        observers.removeAll { $0 === testObserver }
    }
}

/// Records a failure. With no test case running, the message goes to the console (stdout, the
/// browser's console), as xctest-dynamic-overlay reports one outside a test.
public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    print("XCTFail\(message.isEmpty ? "" : ": \(message)") (\(file):\(line))")
}
#endif
