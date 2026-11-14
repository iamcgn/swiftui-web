// TipKit's datastore: each tip's displays and invalidation, the parameters, the event donations
// and the configuration, kept in the app's user defaults (the page's storage) and told to the
// views that show tips when anything changes.
import WebFoundation
import Observation

/// Tells the tip views to read the store again.
@MainActor @Observable
final class _TipsObserver {
    static let shared = _TipsObserver()
    var revision = 0
}

final class _TipStore: @unchecked Sendable {
    static let shared = _TipStore()

    enum Testing: Equatable { case none, showAll, hideAll, show(Set<String>), hide(Set<String>) }

    struct TipRecord: Codable {
        var displayCount = 0
        var displayedSeconds: TimeInterval = 0
        var firstDisplay: Date?
        var invalidation: Tips.InvalidationReason?
    }

    struct DonationRecord: Codable {
        var date: Date
        var info: Data
    }

    struct Saved: Codable {
        var tips: [String: TipRecord] = [:]
        var parameters: [String: Data] = [:]
        var donations: [String: [DonationRecord]] = [:]
        /// When a tip first showed most recently (the display frequency counts from it).
        var lastFirstDisplay: Date?
    }

    private let lock = NSLock()
    private var saved = Saved()
    private var transientParameters: [String: Data] = [:]
    private var loaded = false
    private(set) var configured = false
    private var frequency: TimeInterval = 0
    private var testing = Testing.none
    private var watchers: [UUID: () -> Void] = [:]
    /// How many views show each tip now: a tip on screen stays until it leaves, even when this
    /// display reached its `MaxDisplayCount`.
    private var onScreen: [String: Int] = [:]

    static let defaultsKey = "com.apple.TipKit.datastore"
    var defaults: UserDefaults = .standard

    // MARK: Configuration

    func configure(_ options: [Tips.ConfigurationOption]) throws {
        lock.lock()
        guard !configured else { lock.unlock(); throw TipKitError.tipsDatastoreAlreadyConfigured }
        configured = true
        for option in options {
            if case .displayFrequency(let interval) = option.kind { frequency = interval }
        }
        loadLocked()
        lock.unlock()
        changed()
    }

    func reset() {
        lock.lock()
        saved = Saved()
        transientParameters = [:]
        loaded = true
        defaults.removeObject(forKey: Self.defaultsKey)
        lock.unlock()
        changed()
    }

    func setTesting(_ mode: Testing) {
        lock.lock(); testing = mode; lock.unlock()
        changed()
    }

    /// Tests: forgets the configuration and everything kept, in memory and in the defaults.
    func _resetForTesting(defaults: UserDefaults = .standard) {
        lock.lock()
        self.defaults = defaults
        defaults.removeObject(forKey: Self.defaultsKey)
        saved = Saved()
        transientParameters = [:]
        onScreen = [:]
        loaded = false
        configured = false
        frequency = 0
        testing = .none
        lock.unlock()
        changed()
    }

    /// Tests: a new launch, which forgets what is in memory and reads the defaults again.
    func _reloadForTesting(defaults: UserDefaults) {
        lock.lock()
        self.defaults = defaults
        saved = Saved()
        transientParameters = [:]
        onScreen = [:]
        loaded = false
        configured = false
        frequency = 0
        testing = .none
        lock.unlock()
        changed()
    }

    /// Tests: every view showing the tip went away.
    func _endAllDisplaysForTesting(_ id: String) {
        lock.lock()
        let count = onScreen[id] ?? 0
        lock.unlock()
        for _ in 0..<count { endDisplay(id, seconds: 0) }
    }

    private func loadLocked() {
        guard !loaded else { return }
        loaded = true
        if let data = defaults.data(forKey: Self.defaultsKey), let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            // Parameters set before `configure` stay.
            decoded.parameters.forEach { key, value in if saved.parameters[key] == nil { saved.parameters[key] = value } }
            saved.tips.merge(decoded.tips) { current, _ in current }
            saved.donations.merge(decoded.donations) { current, old in old + current }
            saved.lastFirstDisplay = saved.lastFirstDisplay ?? decoded.lastFirstDisplay
        }
    }

    private func saveLocked() {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    // MARK: Parameters and events

    func parameter<Value: Decodable>(_ id: String, as type: Value.Type) -> Value? {
        lock.lock(); defer { lock.unlock() }
        loadLocked()
        guard let data = transientParameters[id] ?? saved.parameters[id] else { return nil }
        return try? JSONDecoder().decode([Value].self, from: data).first
    }

    func setParameter<Value: Encodable>(_ id: String, _ value: Value, transient: Bool) {
        guard let data = try? JSONEncoder().encode([value]) else { return }
        lock.lock()
        loadLocked()
        if transient { transientParameters[id] = data } else { saved.parameters[id] = data; saveLocked() }
        lock.unlock()
        changed()
    }

    func donations(_ id: String) -> [DonationRecord] {
        lock.lock(); defer { lock.unlock() }
        loadLocked()
        return saved.donations[id] ?? []
    }

    func donate(_ id: String, info: Data) {
        lock.lock()
        loadLocked()
        saved.donations[id, default: []].append(DonationRecord(date: Date(), info: info))
        saveLocked()
        lock.unlock()
        changed()
    }

    // MARK: Tips

    func status<T: Tip>(of tip: T) -> Tips.Status {
        let id = tip.id
        let typeName = String(reflecting: T.self)
        lock.lock()
        loadLocked()
        let configured = configured, testing = testing, record = saved.tips[id] ?? TipRecord(), showing = onScreen[id] != nil
        let lastFirstDisplay = saved.lastFirstDisplay, frequency = frequency
        lock.unlock()
        switch testing {
        case .showAll: return .available
        case .hideAll: return .pending
        case .show(let names) where names.contains(typeName): return .available
        case .hide(let names) where names.contains(typeName): return .pending
        default: break
        }
        if let reason = record.invalidation { return .invalidated(reason) }
        guard configured else { return .pending }
        let options = tip.options
        if let max = options.lazy.compactMap({ $0 as? Tips.MaxDisplayCount }).first?.count, record.displayCount >= max, !showing {
            return .invalidated(.displayCountExceeded)
        }
        if let max = options.lazy.compactMap({ $0 as? Tips.MaxDisplayDuration }).first?.duration, record.displayedSeconds >= max, !showing {
            return .invalidated(.displayDurationExceeded)
        }
        guard tip.rules.allSatisfy({ $0.holds() }) else { return .pending }
        // A tip that has not shown yet waits its turn when another tip first showed within the
        // display frequency.
        let ignoresFrequency = options.contains { ($0 as? Tips.IgnoresDisplayFrequency)?.ignores == true }
        if record.firstDisplay == nil, !ignoresFrequency, frequency > 0, let last = lastFirstDisplay, Date().timeIntervalSince(last) < frequency {
            return .pending
        }
        return .available
    }

    /// A view shows the tip: its display count goes up (the first time, the display frequency
    /// starts counting from now).
    func beginDisplay(_ id: String) {
        lock.lock()
        var record = saved.tips[id] ?? TipRecord()
        record.displayCount += 1
        if record.firstDisplay == nil {
            record.firstDisplay = Date()
            saved.lastFirstDisplay = record.firstDisplay
        }
        saved.tips[id] = record
        onScreen[id, default: 0] += 1
        saveLocked()
        lock.unlock()
    }

    /// A view stopped showing the tip after `seconds`.
    func endDisplay(_ id: String, seconds: TimeInterval) {
        lock.lock()
        saved.tips[id, default: TipRecord()].displayedSeconds += max(seconds, 0)
        if let count = onScreen[id] { onScreen[id] = count > 1 ? count - 1 : nil }
        saveLocked()
        lock.unlock()
        changed()
    }

    func displayCount(_ id: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return saved.tips[id]?.displayCount ?? 0
    }

    func invalidate(_ id: String, reason: Tips.InvalidationReason) {
        lock.lock()
        loadLocked()
        guard saved.tips[id]?.invalidation == nil else { lock.unlock(); return }
        saved.tips[id, default: TipRecord()].invalidation = reason
        saveLocked()
        lock.unlock()
        changed()
    }

    func resetEligibility(_ id: String) {
        lock.lock()
        saved.tips[id] = TipRecord()
        saveLocked()
        lock.unlock()
        changed()
    }

    // MARK: Updates

    /// A stream of `value()`, yielded now and again whenever it changes.
    func updates<Value: Equatable & Sendable>(_ value: @escaping @Sendable () -> Value) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let key = UUID()
            nonisolated(unsafe) var last = value()
            continuation.yield(last)
            lock.lock()
            watchers[key] = {
                let current = value()
                if current != last { last = current; continuation.yield(current) }
            }
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.watchers[key] = nil; self.lock.unlock()
            }
        }
    }

    /// Something changed: the streams re-read their values and the views redraw.
    func changed() {
        lock.lock()
        let watchers = Array(watchers.values)
        lock.unlock()
        for watcher in watchers { watcher() }
        if Thread.isMainThread {
            MainActor.assumeIsolated { _TipsObserver.shared.revision += 1 }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { _TipsObserver.shared.revision += 1 } }
        }
    }
}

/// Hooks for TipKit's own tests: not part of Apple's API.
public enum _TipStoreTestHook {
    public static func reset(_ defaults: UserDefaults) { _TipStore.shared._resetForTesting(defaults: defaults) }
    public static func reload(_ defaults: UserDefaults) { _TipStore.shared._reloadForTesting(defaults: defaults) }
    public static func endAllDisplays(of id: String) { _TipStore.shared._endAllDisplaysForTesting(id) }
}
