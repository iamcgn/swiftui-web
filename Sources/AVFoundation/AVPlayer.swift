// AVFoundation's player for SwiftUIWeb (sw-frameworks, decision 0018): the members apps use
// with `VideoPlayer`. The player holds the state the host's `<video>` element follows (the
// source, playing, muted, looping, the rate); there is no media pipeline of its own, so
// times and durations are what the host reports back — nothing yet.
#if os(WASI)
@_exported import WebFoundation   // as Apple's AVFoundation re-exports Foundation
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
public struct CMTime: Hashable, Sendable {
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
    public func hash(into hasher: inout Hasher) {
        if seconds.isNaN { hasher.combine(0 as UInt8) } else { hasher.combine(seconds) }
    }
    public static let zero = CMTime(seconds: 0)
    public static let invalid = CMTime(seconds: .nan)
    public static let positiveInfinity = CMTime(seconds: .infinity)
    public static let negativeInfinity = CMTime(seconds: -.infinity)
    public static let indefinite = CMTime(seconds: .nan)
    public var isValid: Bool { !seconds.isNaN }
}

public typealias CMTimeValue = Int64
public typealias CMTimeScale = Int32

public func CMTimeMake(value: Int64, timescale: Int32) -> CMTime { CMTime(value: value, timescale: timescale) }
public func CMTimeMakeWithSeconds(_ seconds: Double, preferredTimescale: Int32) -> CMTime { CMTime(seconds: seconds, preferredTimescale: preferredTimescale) }
public func CMTimeGetSeconds(_ time: CMTime) -> Double { time.seconds }

/// An item a player plays: a URL, and the asset it was made from.
public final class AVPlayerItem: @unchecked Sendable {
    public let url: URL
    public let asset: AVAsset
    /// Where the item was last sought to (the host's element plays from there).
    private var position: Double?
    public init(url: URL) {
        self.url = url
        asset = AVURLAsset(url: url)
    }
    public init(asset: AVAsset) {
        url = asset.url
        self.asset = asset
    }
    public var duration: CMTime { .invalid }
    public var status: AVPlayerItem.Status { .unknown }
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }

    /// The item's time: where it was last sought to (the host does not report its playhead yet).
    public func currentTime() -> CMTime { CMTime(seconds: position ?? 0) }
    /// Moves the item to `time`; the handler, if any, hears that the seek finished.
    public func seek(to time: CMTime, completionHandler: (@Sendable (Bool) -> Void)? = nil) {
        seek(to: time, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity, completionHandler: completionHandler)
    }
    /// Moves the item to `time` (the browser seeks to the exact time whatever the tolerances).
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: (@Sendable (Bool) -> Void)? = nil) {
        guard time.isValid else { completionHandler?(false); return }
        position = time.seconds
        completionHandler?(true)
    }
    /// Ends seeks not yet finished (each seek here finishes at once).
    public func cancelPendingSeeks() {}
}

/// Plays one item: `play()`, `pause()`, the rate, muting, looping through `actionAtItemEnd`.
@MainActor @Observable
public class AVPlayer {
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
    /// Whether the host shows transport controls (`VideoPlayer` shows them; apps hide them
    /// through the view's `_controls`).
    package var showsControls = true
    package var loopStorage = false

    public enum ActionAtItemEnd: Int, Sendable { case advance, pause, none }
    public enum TimeControlStatus: Int, Sendable { case paused, waitingToPlayAtSpecifiedRate, playing }
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }

    public init() {}
    public init(url: URL) { currentItem = AVPlayerItem(url: url) }
    public init(playerItem: AVPlayerItem?) { currentItem = playerItem }

    public var status: Status { currentItem == nil ? .unknown : .readyToPlay }
    public var timeControlStatus: TimeControlStatus { rate == 0 ? .paused : .playing }
    public var isPlaying: Bool { rate != 0 }

    public func play() { if rate == 0 { rate = 1 } }
    public func pause() { rate = 0 }
    public func replaceCurrentItem(with item: AVPlayerItem?) { currentItem = item }
    /// The current item's time (zero with no item).
    public func currentTime() -> CMTime { currentItem?.currentTime() ?? .zero }
    public func seek(to time: CMTime) { currentItem?.seek(to: time) }
    public func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        guard let currentItem else { completionHandler(false); return }
        currentItem.seek(to: time, completionHandler: completionHandler)
    }
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        currentItem?.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
    }
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        guard let currentItem else { completionHandler(false); return }
        currentItem.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter, completionHandler: completionHandler)
    }
    public func seek(to date: Date) {}
    public func addPeriodicTimeObserver(forInterval interval: CMTime, queue: Any? = nil, using block: @escaping @Sendable (CMTime) -> Void) -> Any { _TimeObserver() }
    public func removeTimeObserver(_ observer: Any) {}
}

/// A queue player plays its items in turn (the first one here).
@MainActor
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
@MainActor
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
