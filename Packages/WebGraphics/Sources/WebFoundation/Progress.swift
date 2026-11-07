// `Progress` for wasm (Alamofire's upload and download progress, `ProgressView(_:)`). It is
// observable: its sets report through Observation, so `observe(\.fractionCompleted)` and a
// progress view follow it. A child added with `addChild(_:withPendingUnitCount:)` counts toward
// its parent's fraction, and adds its pending units to the parent's completed count once it
// finishes. `Progress.current()` and implicit children are not kept: nothing becomes current.
#if os(WASI)
import Observation

/// What kind of work a progress reports.
public struct ProgressKind: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let file = ProgressKind(rawValue: "NSProgressKindFile")
}

/// A key in a progress's `userInfo`.
public struct ProgressUserInfoKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let estimatedTimeRemainingKey = ProgressUserInfoKey("NSProgressEstimatedTimeRemainingKey")
    public static let throughputKey = ProgressUserInfoKey("NSProgressThroughputKey")
    public static let fileCompletedCountKey = ProgressUserInfoKey("NSProgressFileCompletedCountKey")
    public static let fileTotalCountKey = ProgressUserInfoKey("NSProgressFileTotalCountKey")
}

open class Progress: NSObject, Observation.Observable, @unchecked Sendable {
    public struct FileOperationKind: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let downloading = FileOperationKind(rawValue: "NSProgressFileOperationKindDownloading")
        public static let decompressingAfterDownloading = FileOperationKind(rawValue: "NSProgressFileOperationKindDecompressingAfterDownloading")
        public static let receiving = FileOperationKind(rawValue: "NSProgressFileOperationKindReceiving")
        public static let copying = FileOperationKind(rawValue: "NSProgressFileOperationKindCopying")
        public static let uploading = FileOperationKind(rawValue: "NSProgressFileOperationKindUploading")
        public static let duplicating = FileOperationKind(rawValue: "NSProgressFileOperationKindDuplicating")
    }

    private let _registrar = ObservationRegistrar()
    private var _total: Int64
    private var _completed: Int64 = 0
    private var _description = ""
    private var _additionalDescription = ""
    private var _cancelled = false
    private var _paused = false
    private var _children: [(progress: Progress, pending: Int64)] = []
    private weak var _parent: Progress?

    open var cancellationHandler: (@Sendable () -> Void)?
    open var pausingHandler: (@Sendable () -> Void)?
    open var resumingHandler: (@Sendable () -> Void)?
    open var isCancellable = true
    open var isPausable = false
    open var kind: ProgressKind?
    open var fileOperationKind: FileOperationKind?
    open var fileURL: URL?
    open var estimatedTimeRemaining: TimeInterval?
    open var throughput: Int?
    open private(set) var userInfo: [ProgressUserInfoKey: Any] = [:]

    public init(totalUnitCount: Int64) {
        _total = totalUnitCount
        super.init()
    }

    public convenience override init() { self.init(totalUnitCount: 0) }

    /// A progress with no parent (nothing becomes current here, so every progress is one).
    public convenience init(parent: Progress?, userInfo: [ProgressUserInfoKey: Any]? = nil) {
        self.init(totalUnitCount: 0)
        self.userInfo = userInfo ?? [:]
    }

    public static func discreteProgress(totalUnitCount: Int64) -> Progress { Progress(totalUnitCount: totalUnitCount) }

    /// A progress whose units count toward `parent`'s pending units.
    public convenience init(totalUnitCount: Int64, parent: Progress, pendingUnitCount: Int64) {
        self.init(totalUnitCount: totalUnitCount)
        parent.addChild(self, withPendingUnitCount: pendingUnitCount)
    }

    /// No progress is ever current here.
    open class func current() -> Progress? { nil }
    open func becomeCurrent(withPendingUnitCount unitCount: Int64) {}
    open func resignCurrent() {}

    open var totalUnitCount: Int64 {
        get { _registrar.access(self, keyPath: \.totalUnitCount); return _total }
        set { _registrar.withMutation(of: self, keyPath: \.totalUnitCount) { _total = newValue }; _changed() }
    }

    open var completedUnitCount: Int64 {
        get { _registrar.access(self, keyPath: \.completedUnitCount); return _completed }
        set { _registrar.withMutation(of: self, keyPath: \.completedUnitCount) { _completed = newValue }; _changed() }
    }

    open var localizedDescription: String! {
        get { _registrar.access(self, keyPath: \.localizedDescription); return _description }
        set { _registrar.withMutation(of: self, keyPath: \.localizedDescription) { _description = newValue ?? "" } }
    }

    open var localizedAdditionalDescription: String! {
        get { _registrar.access(self, keyPath: \.localizedAdditionalDescription); return _additionalDescription }
        set { _registrar.withMutation(of: self, keyPath: \.localizedAdditionalDescription) { _additionalDescription = newValue ?? "" } }
    }

    open var isCancelled: Bool {
        _registrar.access(self, keyPath: \.isCancelled)
        return _cancelled || (_parent?.isCancelled ?? false)
    }

    open var isPaused: Bool {
        _registrar.access(self, keyPath: \.isPaused)
        return _paused
    }

    /// Zero to one, children's fractions counted by their pending units; zero while the total is
    /// zero or less.
    open var fractionCompleted: Double {
        let total = totalUnitCount
        guard total > 0 else { return 0 }
        var done = Double(completedUnitCount)
        for child in _children { done += child.progress.fractionCompleted * Double(child.pending) }
        return min(max(done / Double(total), 0), 1)
    }

    open var isIndeterminate: Bool {
        let total = totalUnitCount, completed = completedUnitCount
        return total < 0 || completed < 0 || (total == 0 && completed == 0)
    }
    open var isFinished: Bool { totalUnitCount > 0 && completedUnitCount >= totalUnitCount }

    open func addChild(_ child: Progress, withPendingUnitCount inUnitCount: Int64) {
        child._parent = self
        _registrar.withMutation(of: self, keyPath: \.completedUnitCount) { _children.append((child, inUnitCount)) }
        child._changed()
    }

    open func setUserInfoObject(_ objectOrNil: Any?, forKey key: ProgressUserInfoKey) { userInfo[key] = objectOrNil }

    open func cancel() {
        guard !_cancelled else { return }
        _registrar.withMutation(of: self, keyPath: \.isCancelled) { _cancelled = true }
        cancellationHandler?()
        for child in _children { child.progress.cancel() }
    }

    open func pause() {
        guard !_paused else { return }
        _registrar.withMutation(of: self, keyPath: \.isPaused) { _paused = true }
        pausingHandler?()
        for child in _children { child.progress.pause() }
    }

    open func resume() {
        guard _paused else { return }
        _registrar.withMutation(of: self, keyPath: \.isPaused) { _paused = false }
        resumingHandler?()
        for child in _children { child.progress.resume() }
    }

    /// A child that finished hands its pending units to its parent; any change reaches the
    /// parent's observers, whose fraction reads the child's.
    private func _changed() {
        guard let parent = _parent, let index = parent._children.firstIndex(where: { $0.progress === self }) else { return }
        if isFinished {
            let pending = parent._children.remove(at: index).pending
            _parent = nil
            parent.completedUnitCount += pending
        } else {
            parent._registrar.withMutation(of: parent, keyPath: \.completedUnitCount) {}
            parent._changed()
        }
    }
}

#endif
