// CADisplayLink (Docs/elements/UIKit/Animation.md): a timer tied to the scene's frame clock.
// There is no Objective-C runtime here, so the link takes a handler rather than a selector:
// `CADisplayLink(target:handler:)` or `CADisplayLink { link in … }`; `add(to:forMode:)` starts
// it (the run loop arguments are accepted and ignored), `invalidate` ends it, `isPaused` holds
// it. `timestamp`, `targetTimestamp` and `duration` follow the frames the host delivers.

/// The frame rate range a display link prefers (`CAFrameRateRange` in Core Animation).
public typealias CAFrameRateRange = CADisplayLink.FrameRateRange

/// A timer object that lets your app synchronize its drawing to the refresh rate of the display.
@MainActor
public final class CADisplayLink {
    public struct FrameRateRange: Equatable, Sendable {
        public var minimum: Float
        public var maximum: Float
        public var preferred: Float?
        public init(minimum: Float, maximum: Float, preferred: Float? = nil) { self.minimum = minimum; self.maximum = maximum; self.preferred = preferred }
        public static let `default` = FrameRateRange(minimum: 0, maximum: 0, preferred: nil)
    }

    private let handler: @MainActor (CADisplayLink) -> Void
    private weak var target: AnyObject?
    private let requiresTarget: Bool
    /// The time of the frame the handler was last called for, and of the next one.
    public private(set) var timestamp: Double = 0
    public private(set) var targetTimestamp: Double = 0
    /// Seconds between frames (the last interval the host delivered; a 60th before the first).
    public private(set) var duration: Double = 1.0 / 60
    public var isPaused = false { didSet { if !isPaused { UIKitScene.shared.setNeedsFrame() } } }
    public var preferredFramesPerSecond = 0
    public var preferredFrameRateRange: FrameRateRange = .default
    public private(set) var isValid = true
    private var isAdded = false

    /// A link calling `handler` with itself each frame while `target` lives.
    public init(target: AnyObject, handler: @escaping @MainActor (CADisplayLink) -> Void) {
        self.target = target
        self.requiresTarget = true
        self.handler = handler
    }

    public init(handler: @escaping @MainActor (CADisplayLink) -> Void) {
        self.requiresTarget = false
        self.handler = handler
    }

    /// Starts the link (the run loop and mode are accepted for source compatibility).
    public func add(to runLoop: AnyObject?, forMode mode: String? = nil) {
        guard isValid, !isAdded else { return }
        isAdded = true
        UIKitScene.shared.displayLinks.append(WeakDisplayLink(link: self))
        UIKitScene.shared.setNeedsFrame()
    }

    public func remove(from runLoop: AnyObject?, forMode mode: String? = nil) {
        isAdded = false
        UIKitScene.shared.displayLinks.removeAll { $0.link === self || $0.link == nil }
    }

    public func invalidate() {
        isValid = false
        remove(from: nil)
    }

    /// A frame passed: the handler runs with the new timestamps.
    func tick(elapsed: Double, now: Double) -> Bool {
        guard isValid, isAdded else { return false }
        if requiresTarget, target == nil { invalidate(); return false }
        guard !isPaused else { return true }
        duration = elapsed > 0 ? elapsed : duration
        timestamp = now
        targetTimestamp = now + duration
        handler(self)
        return isValid && isAdded
    }
}

struct WeakDisplayLink {
    weak var link: CADisplayLink?
}
