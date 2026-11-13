// BackgroundTasks on the web: an app is in the background while its page is hidden (another tab,
// a minimised window), and the browser keeps running it there, more slowly. So the scheduler
// launches the work an app asked for when the app goes to the background: each app refresh and
// processing request whose earliest begin date has come (a later one when its date comes, while
// the app is still in the background). An app refresh task has 30 seconds before its expiration
// handler runs; a processing task runs until the app comes back to the foreground. A page cannot
// tell whether the computer is plugged in, so a processing request that requires external power
// waits. The launch handler is the one registered for the identifier, or the action of SwiftUI's
// `backgroundTask(.appRefresh(_:))` scene modifier. A closed page runs nothing.
// Apple's frameworks re-export Foundation: a file importing only this module names Date.
@_exported import WebFoundation
import BackgroundTasksHost

// MARK: - Requests

/// A request to launch the app in the background to do work.
open class BGTaskRequest: NSObject, @unchecked Sendable {
    /// The identifier of the task (one of the app's `BGTaskSchedulerPermittedIdentifiers`).
    public let identifier: String
    /// The earliest date the task may run (`nil`: as soon as the app is in the background).
    open var earliestBeginDate: Date?

    init(_identifier identifier: String) {
        self.identifier = identifier
        super.init()
    }
}

/// A request to launch the app briefly to refresh its content.
open class BGAppRefreshTaskRequest: BGTaskRequest, @unchecked Sendable {
    public init(identifier: String) { super.init(_identifier: identifier) }
}

/// A request to launch the app for longer work, such as maintenance.
open class BGProcessingTaskRequest: BGTaskRequest, @unchecked Sendable {
    /// Whether the work needs the network (a page that is running has it).
    open var requiresNetworkConnectivity = false
    /// Whether the work waits for the device to be charging (a page cannot tell, so it waits).
    open var requiresExternalPower = false
    public init(identifier: String) { super.init(_identifier: identifier) }
}

/// A request to launch the app to process health research data.
open class BGHealthResearchTaskRequest: BGProcessingTaskRequest, @unchecked Sendable {
    /// The file protection the data needs (`FileProtectionType`'s raw value).
    open var protectionTypeOfRequiredData = "NSFileProtectionCompleteUntilFirstUserAuthentication"
}

// MARK: - Tasks

/// Background work the scheduler launched: the app does it and says when it is done.
open class BGTask: NSObject, @unchecked Sendable {
    /// The identifier of the request that launched it.
    public let identifier: String
    /// Runs when the task's time is up, before it is ended: the app stops its work here.
    open var expirationHandler: (() -> Void)?
    var finished: ((_ expired: Bool) -> Void)?
    var completed = false

    init(_identifier identifier: String) {
        self.identifier = identifier
        super.init()
    }

    /// Tells the scheduler the work is done.
    open func setTaskCompleted(success: Bool) {
        guard !completed else { return }
        completed = true
        finished?(false)
        finished = nil
    }

    /// The time is up: the expiration handler runs, then the task ends.
    func expire() {
        guard !completed else { return }
        expirationHandler?()
        completed = true
        finished?(true)
        finished = nil
    }
}

/// A task that refreshes the app's content (30 seconds).
open class BGAppRefreshTask: BGTask, @unchecked Sendable {}
/// A task for longer work (until the app comes back to the foreground).
open class BGProcessingTask: BGTask, @unchecked Sendable {}
/// A task that processes health research data.
open class BGHealthResearchTask: BGProcessingTask, @unchecked Sendable {}

// MARK: - Scheduler

/// Keeps the app's requests and launches their tasks while the app is in the background.
open class BGTaskScheduler: NSObject, @unchecked Sendable {
    /// Why a request was not taken.
    public struct Error: Swift.Error, Hashable, Sendable, CustomStringConvertible {
        public enum Code: Int, Hashable, Sendable {
            /// The app cannot schedule background work (background refresh is off).
            case unavailable = 1
            /// The app has as many requests of the kind as it may (one refresh, ten processing).
            case tooManyPendingTaskRequests = 2
            /// The identifier is not one the app may schedule.
            case notPermitted = 3
            /// The task cannot run right away.
            case immediateRunIneligible = 4
        }
        public let code: Code
        public init(_ code: Code) { self.code = code }
        public static var errorDomain: String { BGTaskSchedulerErrorDomain }
        public static var unavailable: Code { .unavailable }
        public static var tooManyPendingTaskRequests: Code { .tooManyPendingTaskRequests }
        public static var notPermitted: Code { .notPermitted }
        public static var immediateRunIneligible: Code { .immediateRunIneligible }
        public var description: String { "\(BGTaskSchedulerErrorDomain) Code=\(code.rawValue)" }
    }

    /// The app's scheduler.
    public static let shared = BGTaskScheduler()

    private let lock = NSLock()
    private var handlers: [String: (queue: DispatchQueue?, handler: (BGTask) -> Void)] = [:]
    private var pending: [BGTaskRequest] = []
    private var running: [ObjectIdentifier: BGTask] = [:]
    private var observing = false

    public override init() { super.init() }

    /// Registers what runs when a task with the identifier launches: the handler, on the queue
    /// (`nil`: the main queue). Returns `false` when the identifier already has one.
    @discardableResult
    open func register(forTaskWithIdentifier identifier: String, using queue: DispatchQueue?, launchHandler: @escaping (BGTask) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard handlers[identifier] == nil else { return false }
        handlers[identifier] = (queue, launchHandler)
        return true
    }

    /// Asks for the request's task to launch. A request with the identifier of one already pending
    /// replaces it; an app keeps at most one app refresh request and ten processing requests.
    open func submit(_ taskRequest: BGTaskRequest) throws {
        guard !taskRequest.identifier.isEmpty else { throw Error(.notPermitted) }
        lock.lock()
        pending.removeAll { $0.identifier == taskRequest.identifier }
        let refresh = taskRequest is BGAppRefreshTaskRequest
        let sameKind = pending.filter { ($0 is BGAppRefreshTaskRequest) == refresh }.count
        guard sameKind < (refresh ? 1 : 10) else {
            lock.unlock()
            throw Error(.tooManyPendingTaskRequests)
        }
        pending.append(taskRequest)
        lock.unlock()
        observeApp()
        Self.onMain { self.launchDue() }
    }

    /// Withdraws the pending request with the identifier.
    open func cancel(taskRequestWithIdentifier identifier: String) {
        lock.lock(); defer { lock.unlock() }
        pending.removeAll { $0.identifier == identifier }
    }

    /// Withdraws every pending request.
    open func cancelAllTaskRequests() {
        lock.lock(); defer { lock.unlock() }
        pending.removeAll()
    }

    /// The requests waiting to launch.
    open func getPendingTaskRequests(completionHandler: @escaping ([BGTaskRequest]) -> Void) {
        completionHandler(pendingCopy)
    }

    /// The requests waiting to launch.
    open func pendingTaskRequests() async -> [BGTaskRequest] { pendingCopy }

    private var pendingCopy: [BGTaskRequest] {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    // MARK: Launching

    private static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(work) } else { DispatchQueue.main.async { MainActor.assumeIsolated(work) } }
    }

    /// Follows the app's state: the host tells the scheduler when it changes, and a UIKit app's
    /// scene reports it through UIApplication's notifications. Installed from whatever thread
    /// first submits, so a launch never waits on a hop to the main actor.
    private func observeApp() {
        lock.lock()
        let first = !observing
        observing = true
        lock.unlock()
        guard first else { return }
        _BackgroundTasksHost.scheduler = { [weak self] inBackground in
            guard let self else { return }
            if inBackground { self.launchDue() } else { self.appCameToForeground() }
        }
        let center = NotificationCenter.default
        _ = center.addObserver(forName: Notification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil, queue: nil) { _ in
            Self.onMain { _BackgroundTasksHost.appStateChanged(inBackground: true) }
        }
        _ = center.addObserver(forName: Notification.Name("UIApplicationWillEnterForegroundNotification"), object: nil, queue: nil) { _ in
            Self.onMain { _BackgroundTasksHost.appStateChanged(inBackground: false) }
        }
    }

    /// Launches the due requests while the app is in the background, and waits for the next one.
    @MainActor private func launchDue() {
        guard _BackgroundTasksHost.inBackground else { return }
        let now = Date()
        lock.lock()
        let due = pending.filter { request in
            if let processing = request as? BGProcessingTaskRequest, processing.requiresExternalPower { return false }
            return (request.earliestBeginDate ?? now) <= now
        }
        pending.removeAll { request in due.contains { $0 === request } }
        let next = pending.compactMap { request -> Date? in
            if let processing = request as? BGProcessingTaskRequest, processing.requiresExternalPower { return nil }
            return request.earliestBeginDate
        }.min()
        lock.unlock()
        for request in due { launch(request) }
        if let next {
            let delay = max(next.timeIntervalSince(Date()), 0)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.launchDue()
            }
        }
    }

    @MainActor private func launch(_ request: BGTaskRequest) {
        let task: BGTask
        switch request {
        case is BGHealthResearchTaskRequest: task = BGHealthResearchTask(_identifier: request.identifier)
        case is BGProcessingTaskRequest: task = BGProcessingTask(_identifier: request.identifier)
        default: task = BGAppRefreshTask(_identifier: request.identifier)
        }
        lock.lock()
        let registered = handlers[request.identifier]
        lock.unlock()
        let action = task is BGAppRefreshTask ? _BackgroundTasksHost.appRefreshActions[request.identifier] : nil
        guard registered != nil || action != nil else { return }

        let key = ObjectIdentifier(task)
        lock.lock(); running[key] = task; lock.unlock()
        task.finished = { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.running[key] = nil; self.lock.unlock()
        }
        if task is BGAppRefreshTask {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.refreshTime)
                task.expire()
            }
        }
        if let registered {
            if let queue = registered.queue, queue !== DispatchQueue.main, queue.label != DispatchQueue.main.label {
                nonisolated(unsafe) let handler = registered.handler
                queue.async { handler(task) }
            } else {
                registered.handler(task)
            }
        } else if let action {
            let work = Task { await action() }
            task.expirationHandler = { work.cancel() }
            Task { @MainActor in
                await work.value
                task.setTaskCompleted(success: !work.isCancelled)
            }
        }
    }

    /// The app is in the foreground again: the processing tasks still running expire.
    @MainActor private func appCameToForeground() {
        lock.lock()
        let processing = running.values.filter { $0 is BGProcessingTask }
        lock.unlock()
        for task in processing { task.expire() }
    }

    /// How long an app refresh task runs before it expires (30 seconds; tests shorten it).
    nonisolated(unsafe) static var refreshTime: UInt64 = 30_000_000_000

    /// Tests: forgets the handlers, the requests and the tasks, and sets the refresh time.
    @MainActor public static func _reset(refreshSeconds: Double = 30) {
        let scheduler = shared
        scheduler.lock.lock()
        scheduler.handlers.removeAll()
        scheduler.pending.removeAll()
        scheduler.running.removeAll()
        scheduler.observing = false
        scheduler.lock.unlock()
        refreshTime = UInt64(refreshSeconds * 1_000_000_000)
    }
}

/// Matches a scheduler error by its code in a `catch` (`catch BGTaskScheduler.Error.notPermitted`).
public func ~= (code: BGTaskScheduler.Error.Code, error: any Error) -> Bool {
    (error as? BGTaskScheduler.Error)?.code == code
}

/// The domain of the scheduler's errors as `NSError`s.
public let BGTaskSchedulerErrorDomain = "BGTaskSchedulerErrorDomain"
