// Operations, their queues and progress, as RevenueCat, SDWebImage, Alamofire and SwiftyBeaver
// use them. The cases run against Foundation on macOS and Linux too; queues are queues of their
// own, as the test process doesn't drain Linux's main queue.
import Testing
import WebFoundation

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func add(_ entry: String) { lock.lock(); entries.append(entry); lock.unlock() }
    var items: [String] { lock.lock(); defer { lock.unlock() }; return entries }
}

#if os(WASI) || canImport(Darwin)
/// An operation that finishes on a later turn and reports its state by hand, as RevenueCat's
/// network operations do. (`executing` and `finished` are NSOperation's own names on Apple
/// platforms, so the state goes by other names.)
private final class LaterOperation: Operation, @unchecked Sendable {
    private var running = false
    private var done = false
    override var isAsynchronous: Bool { true }
    override var isExecuting: Bool { running }
    override var isFinished: Bool { done }

    override func start() {
        willChangeValue(forKey: "isExecuting")
        running = true
        didChangeValue(forKey: "isExecuting")
        Task { self.finish() }
    }

    private func finish() {
        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        running = false
        done = true
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }
}
#endif

@Suite struct OperationsAndProgressTests {
    @Test func dependenciesRunFirst() async {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let log = Log()
        let first = BlockOperation { log.add("first") }
        let second = BlockOperation { log.add("second") }
        let third = BlockOperation { log.add("third") }
        third.addDependency(second)
        second.addDependency(first)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            third.completionBlock = { done.resume() }
            queue.addOperations([third, second, first], waitUntilFinished: false)
        }
        #expect(log.items == ["first", "second", "third"])
        #expect(first.isFinished && second.isFinished && third.isFinished)
    }

    @Test func aCancelledOperationFinishesWithoutRunning() async {
        let queue = OperationQueue()
        queue.isSuspended = true
        let log = Log()
        let operation = BlockOperation { log.add("ran") }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            operation.completionBlock = { done.resume() }
            queue.addOperation(operation)
            operation.cancel()
            queue.isSuspended = false
        }
        #expect(operation.isCancelled && operation.isFinished)
        #expect(log.items.isEmpty)
    }

    #if os(WASI) || canImport(Darwin)
    @Test func anAsynchronousOperationHoldsItsDependents() async {
        let queue = OperationQueue()
        let log = Log()
        let later = LaterOperation()
        let after = BlockOperation { log.add(later.isFinished ? "after a finished one" : "too early") }
        after.addDependency(later)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            after.completionBlock = { done.resume() }
            queue.addOperations([after, later], waitUntilFinished: false)
        }
        #expect(log.items == ["after a finished one"])
    }

    @Test func aBarrierHoldsLaterOperations() async {
        let queue = OperationQueue()
        queue.isSuspended = true
        queue.maxConcurrentOperationCount = 2
        let log = Log()
        let earlier = LaterOperation()
        let later = BlockOperation { log.add(earlier.isFinished ? "after finished" : "after before finish") }
        later.queuePriority = .veryHigh
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.addOperation(earlier)
            queue.addBarrierBlock { log.add("barrier") }
            queue.addOperation(later)
            queue.addBarrierBlock { log.add("second barrier") }
            queue.addOperation { log.add("last") }
            queue.addBarrierBlock { done.resume() }
            queue.isSuspended = false
        }
        #expect(log.items == ["barrier", "after finished", "second barrier", "last"])
    }

    @Test func fileCoordinationRunsTheAccessor() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coordinated.txt")
        var error: NSError?
        var seen: URL?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &error) { seen = $0 }
        #expect(seen?.lastPathComponent == "coordinated.txt")
        #expect(error == nil)
    }
    #endif

    @Test func childProgressCountsTowardItsParent() {
        let parent = Progress(totalUnitCount: 10)
        let child = Progress(totalUnitCount: 4)
        parent.addChild(child, withPendingUnitCount: 6)
        parent.completedUnitCount = 2
        child.completedUnitCount = 2
        #expect(abs(parent.fractionCompleted - 0.5) < 1e-9)
        child.completedUnitCount = 4
        #expect(parent.completedUnitCount == 8)
        #expect(abs(parent.fractionCompleted - 0.8) < 1e-9)
        #expect(!parent.isIndeterminate && !parent.isFinished)
        parent.cancel()
        #expect(parent.isCancelled)
    }

    #if os(WASI)
    @Test func olderFragmentOptionName() throws {
        let value = try JSONSerialization.jsonObject(with: Data("3".utf8), options: .allowFragments)
        #expect((value as? NSNumber)?.intValue == 3 || (value as? Int) == 3)
    }
    #endif
}
