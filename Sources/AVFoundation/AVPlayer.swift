// AVFoundation's player for SwiftUIWeb (sw-frameworks, decision 0018): the members apps use
// with `VideoPlayer`. The player holds the state the host's `<video>` element follows (the
// source, playing, muted, looping, the rate); there is no media pipeline of its own, so
// times and durations are what the host reports back — nothing yet.
#if os(WASI)
@_exported import WebFoundation   // as Apple's AVFoundation re-exports Foundation
import UIKitWebCore   // NSValue (WebGraphics, which it re-exports), for the item's time ranges
#else
import Foundation
#endif
import Observation
// The audio half is AVFAudio, as on Apple's platforms, where AVFoundation re-exports it; the
// browser host links only AVFAudio, so an app that never uses the player or the camera carries
// neither (decision 0006).
@_exported import AVFAudio

/// A time in seconds (CoreMedia's `CMTime` reduced to what the hosts can seek to), with the
/// timescale it was made in. Two times are equal when they are the same number of seconds, as
/// `CMTimeCompare` has it, whatever their timescales.
public struct CMTime: Hashable, Comparable, Sendable {
    public var seconds: Double
    /// The units of a second the time counts in (600 unless it was made with another).
    public var timescale: CMTimeScale
    public init(seconds: Double, preferredTimescale: Int32 = 600) {
        self.seconds = seconds
        timescale = preferredTimescale
    }
    /// `value / timescale` seconds (a frame duration: `CMTime(value: 1, timescale: 30)`).
    public init(value: CMTimeValue, timescale: CMTimeScale) {
        seconds = timescale == 0 ? .nan : Double(value) / Double(timescale)
        self.timescale = timescale
    }
    /// The time in units of `timescale`, rounded (0 for a time that is not a number of seconds).
    public var value: CMTimeValue {
        let units = (seconds * Double(timescale)).rounded()
        return units.isFinite && abs(units) < 9.2e18 ? CMTimeValue(units) : 0
    }
    public static func == (a: CMTime, b: CMTime) -> Bool {
        a.seconds == b.seconds || (a.seconds.isNaN && b.seconds.isNaN)
    }
    /// Earlier first, as `CMTimeCompare` orders them; an invalid time comes before every valid one.
    public static func < (a: CMTime, b: CMTime) -> Bool {
        if a.seconds.isNaN || b.seconds.isNaN { return a.seconds.isNaN && !b.seconds.isNaN }
        return a.seconds < b.seconds
    }
    public func hash(into hasher: inout Hasher) {
        if seconds.isNaN { hasher.combine(0 as UInt8) } else { hasher.combine(seconds) }
    }
    public static let zero = CMTime(seconds: 0)
    public static let invalid = CMTime(seconds: .nan)
    public static let positiveInfinity = CMTime(seconds: .infinity)
    public static let negativeInfinity = CMTime(seconds: -.infinity)
    public static let indefinite = CMTime(seconds: .nan)
    public var isValid: Bool { !seconds.isNaN }

    /// The sum or difference of two times, counted in the least common multiple of their
    /// timescales as `CMTimeAdd` counts it (the larger timescale when that would overflow), so
    /// `value` and `timescale` hold the exact answer: 1/1 + 1/4 is 5/4.
    static func _combine(_ lhs: CMTime, _ rhs: CMTime, subtracting: Bool) -> CMTime {
        CMTime(seconds: subtracting ? lhs.seconds - rhs.seconds : lhs.seconds + rhs.seconds,
               preferredTimescale: _commonTimescale(lhs.timescale, rhs.timescale))
    }
    static func _commonTimescale(_ a: CMTimeScale, _ b: CMTimeScale) -> CMTimeScale {
        guard a > 0, b > 0 else { return Swift.max(a, b) }
        var x = Int64(a), y = Int64(b)
        while y != 0 { (x, y) = (y, x % y) }
        let lcm = Int64(a) / x * Int64(b)
        return lcm <= Int64(CMTimeScale.max) ? CMTimeScale(lcm) : Swift.max(a, b)
    }
    public static func + (lhs: CMTime, rhs: CMTime) -> CMTime { _combine(lhs, rhs, subtracting: false) }
    public static func - (lhs: CMTime, rhs: CMTime) -> CMTime { _combine(lhs, rhs, subtracting: true) }
}

public func CMTimeAdd(_ lhs: CMTime, _ rhs: CMTime) -> CMTime { lhs + rhs }
public func CMTimeSubtract(_ lhs: CMTime, _ rhs: CMTime) -> CMTime { lhs - rhs }

public typealias CMTimeValue = Int64
public typealias CMTimeScale = Int32

public func CMTimeMake(value: Int64, timescale: Int32) -> CMTime { CMTime(value: value, timescale: timescale) }
public func CMTimeMakeWithSeconds(_ seconds: Double, preferredTimescale: Int32) -> CMTime { CMTime(seconds: seconds, preferredTimescale: preferredTimescale) }
public func CMTimeGetSeconds(_ time: CMTime) -> Double { time.seconds }
/// -1, 0 or 1 as `time1` is earlier than, the same as or later than `time2`.
public func CMTimeCompare(_ time1: CMTime, _ time2: CMTime) -> Int32 { time1 < time2 ? -1 : time1 == time2 ? 0 : 1 }
public func CMTimeMinimum(_ time1: CMTime, _ time2: CMTime) -> CMTime { min(time1, time2) }
public func CMTimeMaximum(_ time1: CMTime, _ time2: CMTime) -> CMTime { max(time1, time2) }

/// A stretch of time: where it starts and how long it lasts (CoreMedia's `CMTimeRange`).
public struct CMTimeRange: Hashable, Sendable {
    public var start: CMTime
    public var duration: CMTime
    public init(start: CMTime, duration: CMTime) {
        self.start = start
        self.duration = duration
    }
    public init(start: CMTime, end: CMTime) {
        self.start = start
        duration = end - start
    }
    /// Where the range ends: its start plus its duration, in their common timescale.
    public var end: CMTime { start + duration }
    public var isValid: Bool { start.isValid && duration.isValid && duration.seconds >= 0 }
    public var isEmpty: Bool { duration.seconds == 0 }
    /// Whether the time is in the range, its start included and its end not.
    public func containsTime(_ time: CMTime) -> Bool { time.seconds >= start.seconds && time.seconds < end.seconds }
    public static let zero = CMTimeRange(start: .zero, duration: .zero)
    public static let invalid = CMTimeRange(start: .invalid, duration: .invalid)
}

public func CMTimeRangeMake(start: CMTime, duration: CMTime) -> CMTimeRange { CMTimeRange(start: start, duration: duration) }
public func CMTimeRangeGetEnd(_ range: CMTimeRange) -> CMTime { range.end }

/// An item a player plays: a URL, and the asset it was made from. An `NSObject`, as Apple's is,
/// so `item.publisher(for: \.status)` and `observe(_:)` reach it (OldOS's YouTube player).
@Observable
public final class AVPlayerItem: NSObject, @unchecked Sendable {
    public let url: URL
    public let asset: AVAsset
    /// Where the item was last sought to: `VideoPlayer` moves the host's element there.
    private var position: Double?
    /// How many seeks the item has had, so a second seek to the same time moves the element too.
    package private(set) var seeks = 0
    public init(url: URL) {
        self.url = url
        asset = AVURLAsset(url: url)
    }
    public init(asset: AVAsset) {
        url = asset.playbackURL()
        self.asset = asset
    }
    public var duration: CMTime { .invalid }
    public var status: AVPlayerItem.Status { .unknown }
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }
    /// Why the item failed (it never has here: the host's element plays it or shows its own error).
    public var error: (any Error)? { nil }
    /// How far ahead the player should buffer, in seconds (0 lets it choose; the browser always does).
    public var preferredForwardBufferDuration: TimeInterval = 0
    /// The time ranges loaded so far, each an `NSValue` holding a `CMTimeRange` (the host does
    /// not report its buffer yet, so none).
    public var loadedTimeRanges: [NSValue] { [] }
    /// The time ranges that can be sought to (none reported yet).
    public var seekableTimeRanges: [NSValue] { [] }
    /// Whether playback should keep up without stalling; the browser buffers, so taken to be so.
    public var isPlaybackLikelyToKeepUp: Bool { true }
    public var isPlaybackBufferEmpty: Bool { false }
    public var isPlaybackBufferFull: Bool { false }

    /// The item's time: where it was last sought to (the host does not report its playhead yet).
    public func currentTime() -> CMTime { CMTime(seconds: position ?? 0) }
    /// Moves the item to `time`: `VideoPlayer`'s element moves there on its next render. The
    /// handler, if any, hears afterwards, on the main actor, that the seek was made.
    public func seek(to time: CMTime, completionHandler: (@Sendable (Bool) -> Void)? = nil) {
        seek(to: time, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity, completionHandler: completionHandler)
    }
    /// Moves the item to `time` (the browser seeks to the exact time whatever the tolerances).
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: (@Sendable (Bool) -> Void)? = nil) {
        guard time.isValid else {
            if let completionHandler { Task { @MainActor in completionHandler(false) } }
            return
        }
        position = time.seconds
        seeks += 1
        if let completionHandler { Task { @MainActor in completionHandler(true) } }
    }
    /// Ends seeks not yet finished (each seek here finishes at once).
    public func cancelPendingSeeks() {}
}

/// What a player does with its video when the app goes to the background.
public enum AVPlayerAudiovisualBackgroundPlaybackPolicy: Int, Sendable {
    case automatic = 1, pauses = 2, continuesIfPossible = 3
}

extension AVPlayerItem {
    /// Posted when an item plays to its end. The host does not report the end yet, so nothing
    /// posts these: an observer added for them is kept and never called.
    public static let didPlayToEndTimeNotification = Notification.Name("AVPlayerItemDidPlayToEndTimeNotification")
    public static let failedToPlayToEndTimeNotification = Notification.Name("AVPlayerItemFailedToPlayToEndTimeNotification")
    public static let playbackStalledNotification = Notification.Name("AVPlayerItemPlaybackStalledNotification")
    public static let timeJumpedNotification = Notification.Name("AVPlayerItemTimeJumpedNotification")
}

extension Notification.Name {
    public static let AVPlayerItemDidPlayToEndTime = AVPlayerItem.didPlayToEndTimeNotification
    public static let AVPlayerItemFailedToPlayToEndTime = AVPlayerItem.failedToPlayToEndTimeNotification
    public static let AVPlayerItemPlaybackStalled = AVPlayerItem.playbackStalledNotification
    public static let AVPlayerItemTimeJumped = AVPlayerItem.timeJumpedNotification
}

/// Plays one item: `play()`, `pause()`, the rate, muting, looping through `actionAtItemEnd`. An
/// `NSObject`, as Apple's is, so `player.publisher(for: \.timeControlStatus)` reports its rate's
/// changes (Observation carries them, WebFoundation's KeyValueObserving.swift).
@preconcurrency @MainActor @Observable
public class AVPlayer: NSObject {
    public private(set) var currentItem: AVPlayerItem?
    /// 0 paused, 1 playing (other rates are passed to the host's element).
    public var rate: Float = 0
    public var isMuted = false
    public var volume: Float = 1
    public var actionAtItemEnd: ActionAtItemEnd = .pause
    public var allowsExternalPlayback = true
    /// Whether the screen stays awake while video plays (the browser decides: a playing video
    /// keeps the display on there already).
    public var preventsDisplaySleepDuringVideoPlayback = true
    /// What happens to the video when the app goes to the background (the browser decides:
    /// a hidden page's video is the browser's to pause).
    public var audiovisualBackgroundPlaybackPolicy: AVPlayerAudiovisualBackgroundPlaybackPolicy = .automatic
    /// Whether the host shows transport controls (`VideoPlayer` shows them; apps hide them
    /// through the view's `_controls`).
    package var showsControls = true
    package var loopStorage = false

    public enum ActionAtItemEnd: Int, Sendable { case advance, pause, none }
    public enum TimeControlStatus: Int, Sendable { case paused, waitingToPlayAtSpecifiedRate, playing }
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }
    /// Why a player waits before it plays at its rate.
    public struct WaitingReason: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let toMinimizeStalls = WaitingReason(rawValue: "AVPlayerWaitingToMinimizeStallsReason")
        public static let evaluatingBufferingRate = WaitingReason(rawValue: "AVPlayerWaitingWhileEvaluatingBufferingRateReason")
        public static let noItemToPlay = WaitingReason(rawValue: "AVPlayerWaitingWithNoItemToPlayReason")
        public static let interstitialEvent = WaitingReason(rawValue: "AVPlayerWaitingDuringInterstitialEventReason")
        public static let waitingForCoordinatedPlayback = WaitingReason(rawValue: "AVPlayerWaitingForCoordinatedPlaybackReason")
    }

    /// Whether the player waits to buffer before it plays (the browser's element decides).
    public var automaticallyWaitsToMinimizeStalling = true

    public override init() { super.init() }
    public init(url: URL) { currentItem = AVPlayerItem(url: url) }
    public init(playerItem: AVPlayerItem?) { currentItem = playerItem }

    public var status: Status { currentItem == nil ? .unknown : .readyToPlay }
    /// Why the player failed (never: the host's element shows its own error).
    public var error: (any Error)? { nil }
    public var timeControlStatus: TimeControlStatus { rate == 0 ? .paused : .playing }
    /// Why the player is waiting: nil, as it never waits here (it is paused or playing).
    public var reasonForWaitingToPlay: WaitingReason? { nil }
    /// Plays at `rate` at once.
    public func playImmediately(atRate rate: Float) { self.rate = rate }
    public var isPlaying: Bool { rate != 0 }

    public func play() { if rate == 0 { rate = 1 } }
    public func pause() { rate = 0 }
    public func replaceCurrentItem(with item: AVPlayerItem?) { currentItem = item }
    /// The current item's time (zero with no item).
    public func currentTime() -> CMTime { currentItem?.currentTime() ?? .zero }
    public func seek(to time: CMTime) { currentItem?.seek(to: time) }
    public func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        guard let currentItem else { Task { @MainActor in completionHandler(false) }; return }
        currentItem.seek(to: time, completionHandler: completionHandler)
    }
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        currentItem?.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
    }
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        guard let currentItem else { Task { @MainActor in completionHandler(false) }; return }
        currentItem.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter, completionHandler: completionHandler)
    }
    public func seek(to date: Date) {}
    public func addPeriodicTimeObserver(forInterval interval: CMTime, queue: Any? = nil, using block: @escaping @Sendable (CMTime) -> Void) -> Any { _TimeObserver() }
    public func removeTimeObserver(_ observer: Any) {}
}

/// A queue player plays its items in turn (the first one here).
@preconcurrency @MainActor
public final class AVQueuePlayer: AVPlayer {
    public private(set) var items: [AVPlayerItem]
    public init(items: [AVPlayerItem]) {
        self.items = items
        super.init(playerItem: items.first)
    }
    public override init() { items = []; super.init() }
    /// A queue of one item, or of none.
    public override init(playerItem item: AVPlayerItem?) {
        items = item.map { [$0] } ?? []
        super.init(playerItem: item)
    }
    public override convenience init(url: URL) { self.init(playerItem: AVPlayerItem(url: url)) }
    public func advanceToNextItem() {
        if !items.isEmpty { items.removeFirst() }
        replaceCurrentItem(with: items.first)
    }
    public func insert(_ item: AVPlayerItem, after afterItem: AVPlayerItem?) {
        items.append(item)
        if currentItem == nil { replaceCurrentItem(with: item) }
    }
}

/// Loops a queue player's item (the host's element loops).
@preconcurrency @MainActor
public final class AVPlayerLooper {
    public let player: AVQueuePlayer
    public init(player: AVQueuePlayer, templateItem: AVPlayerItem) {
        self.player = player
        player.actionAtItemEnd = .none
        player.loops = true
        if player.currentItem == nil { player.replaceCurrentItem(with: templateItem) }
    }
    public func disableLooping() { player.loops = false }
}

extension AVPlayer {
    /// Set by `AVPlayerLooper`; `VideoPlayer` passes it to the host.
    package var loops: Bool {
        get { loopStorage }
        set { loopStorage = newValue }
    }
}

/// The token a periodic time observer returns (no clock drives it yet).
final class _TimeObserver: Sendable {}
