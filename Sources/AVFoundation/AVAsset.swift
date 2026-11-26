// A movie as AVFoundation's asset loading sees it: `load(.duration)`, `load(.tracks)` and
// `loadTracks(withMediaType:)`, which players read before they show a scrubber or sound controls
// (Mlem's video view does both). The host (`_AVFrameHost.info`, which SwiftUIWebCanvas installs)
// loads the movie's metadata in a hidden `<video>` once per asset: its length, its picture's size
// and, where the browser says, whether it has sound. A movie whose sound the browser does not
// report is taken to have some, so its sound controls show. Without a host, or for a movie the
// browser cannot load, loading throws AVFoundation's `fileFormatNotRecognized` error, as Apple's
// does for a file it cannot read.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(CoreGraphics) && !os(WASI)
import CoreGraphics
#endif
import UIKitWebCore
import AVCaptureHost

/// A media asset by URL. An `NSObject`, as Apple's is.
open class AVAsset: NSObject, @unchecked Sendable {
    public let url: URL
    public init(url: URL) {
        self.url = url
        super.init()
    }
    /// The URL the browser loads the movie from: the asset's own (an `AVURLAsset` with a
    /// resource loader's delegate may answer with the movie's bytes instead).
    func playbackURL() -> URL { url }
    /// The host's one read of the movie, shared by every load.
    nonisolated(unsafe) private var info: Task<_AVMovieInfo, any Error>?
    /// That read, once it has come back.
    nonisolated(unsafe) private var loadedInfo: _AVMovieInfo?

    /// The movie's length, once a `load(_:)` has read the movie's metadata; `.invalid` before
    /// (Apple's waits for the metadata, and is deprecated for `load(.duration)`, which waits
    /// here too).
    public var duration: CMTime {
        guard let loadedInfo else { return .invalid }
        return Self.time(loadedInfo.duration)
    }

    /// The value of one of the asset's properties, once the movie's metadata is loaded.
    public func load<T>(_ property: AVAsyncProperty<AVAsset, T>) async throws -> T {
        let info = try await movieInfo()
        return try Self.value(property, of: self, info)
    }

    /// The values of two of the asset's properties.
    public func load<A, B>(_ a: AVAsyncProperty<AVAsset, A>, _ b: AVAsyncProperty<AVAsset, B>) async throws -> (A, B) {
        let info = try await movieInfo()
        return (try Self.value(a, of: self, info), try Self.value(b, of: self, info))
    }

    /// The values of three of the asset's properties.
    public func load<A, B, C>(_ a: AVAsyncProperty<AVAsset, A>, _ b: AVAsyncProperty<AVAsset, B>,
                              _ c: AVAsyncProperty<AVAsset, C>) async throws -> (A, B, C) {
        let info = try await movieInfo()
        return (try Self.value(a, of: self, info), try Self.value(b, of: self, info), try Self.value(c, of: self, info))
    }

    /// The asset's tracks of one kind: `.video` for its picture, `.audio` for its sound.
    public func loadTracks(withMediaType mediaType: AVMediaType) async throws -> [AVAssetTrack] {
        try await load(.tracks).filter { $0.mediaType == mediaType }
    }

    /// The asset's tracks of one kind, to a handler: the tracks, or the error loading met.
    public func loadTracks(withMediaType mediaType: AVMediaType, completionHandler: @escaping @Sendable ([AVAssetTrack]?, (any Error)?) -> Void) {
        Task {
            do { completionHandler(try await loadTracks(withMediaType: mediaType), nil) } catch { completionHandler(nil, error) }
        }
    }

    /// The track with this ID, if the asset has one.
    public func loadTrack(withTrackID trackID: CMPersistentTrackID) async throws -> AVAssetTrack? {
        try await load(.tracks).first { $0.trackID == trackID }
    }

    @MainActor private func movieInfo() async throws -> _AVMovieInfo {
        if let info { return try await info.value }
        let url = playbackURL().absoluteString
        let task = Task { @MainActor () throws -> _AVMovieInfo in
            guard let host = _AVFrameHost.info else { throw AVError(.fileFormatNotRecognized) }
            let read: _AVMovieInfo? = await withCheckedContinuation { reading in host(url) { reading.resume(returning: $0) } }
            guard let read else { throw AVError(.fileFormatNotRecognized) }
            self.loadedInfo = read
            return read
        }
        info = task
        return try await task.value
    }

    private static func time(_ seconds: Double) -> CMTime {
        seconds.isNaN ? .invalid : seconds.isInfinite ? .indefinite : CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private static func value<T>(_ property: AVAsyncProperty<AVAsset, T>, of asset: AVAsset, _ info: _AVMovieInfo) throws -> T {
        let value: Any?
        switch property.key {
        case "duration": value = time(info.duration)
        case "tracks": value = tracks(of: asset, info)
        case "isPlayable": value = true
        default: value = nil
        }
        guard let value = value as? T else { throw AVError(.operationNotSupportedForAsset) }
        return value
    }

    /// A video track for a picture and an audio track for sound (taken to be there when the
    /// browser does not say).
    private static func tracks(of asset: AVAsset, _ info: _AVMovieInfo) -> [AVAssetTrack] {
        var tracks: [AVAssetTrack] = []
        if info.width > 0, info.height > 0 {
            tracks.append(AVAssetTrack(asset: asset, trackID: 1, mediaType: .video,
                                       naturalSize: CGSize(width: CGFloat(info.width), height: CGFloat(info.height))))
        }
        if info.hasAudio ?? true {
            tracks.append(AVAssetTrack(asset: asset, trackID: CMPersistentTrackID(tracks.count + 1), mediaType: .audio, naturalSize: .zero))
        }
        return tracks
    }
}

/// An asset at a URL, with the loader its delegate answers through for URLs the browser cannot
/// fetch (AVAssetResourceLoader.swift).
open class AVURLAsset: AVAsset, @unchecked Sendable {
    public let resourceLoader = AVAssetResourceLoader()
    /// The URL made for the bytes the delegate answered with, once it has.
    private var answered: URL?

    public init(url: URL, options: [String: Any]? = nil) { super.init(url: url) }

    override func playbackURL() -> URL {
        if let answered { return answered }
        guard !Self.webSchemes.contains(url.scheme?.lowercased() ?? ""), let loaded = resourceLoader.load(url),
              let made = Self.playableURL(for: loaded.data, contentType: loaded.contentType) else { return url }
        answered = made
        return made
    }
}

public typealias CMPersistentTrackID = Int32

/// One of an asset's tracks: its picture or its sound.
public final class AVAssetTrack: @unchecked Sendable {
    public let asset: AVAsset?
    public let trackID: CMPersistentTrackID
    public let mediaType: AVMediaType
    /// The picture's size in pixels (zero for sound).
    public let naturalSize: CGSize
    public var isPlayable: Bool { true }
    public var isEnabled: Bool { true }
    init(asset: AVAsset, trackID: CMPersistentTrackID, mediaType: AVMediaType, naturalSize: CGSize) {
        self.asset = asset
        self.trackID = trackID
        self.mediaType = mediaType
        self.naturalSize = naturalSize
    }

    /// The value of one of the track's properties (each is known once the asset's tracks are).
    public func load<T>(_ property: AVAsyncProperty<AVAssetTrack, T>) async throws -> T {
        let value: Any?
        switch property.key {
        case "naturalSize": value = naturalSize
        case "isPlayable": value = isPlayable
        case "isEnabled": value = isEnabled
        default: value = nil
        }
        guard let value = value as? T else { throw AVError(.operationNotSupportedForAsset) }
        return value
    }
}

/// A property an asset or a track loads, whatever its value's type.
public class AVPartialAsyncProperty<Root>: @unchecked Sendable {
    let key: String
    init(key: String) { self.key = key }
}

/// A property an asset or a track loads: `asset.load(.duration)`.
public final class AVAsyncProperty<Root, Value>: AVPartialAsyncProperty<Root>, @unchecked Sendable {}

extension AVPartialAsyncProperty where Root == AVAsset {
    /// How long the movie runs (`.invalid` when the browser cannot tell, `.indefinite` for a live stream).
    public static var duration: AVAsyncProperty<AVAsset, CMTime> { .init(key: "duration") }
    /// The movie's tracks: a video track for its picture, an audio track for its sound.
    public static var tracks: AVAsyncProperty<AVAsset, [AVAssetTrack]> { .init(key: "tracks") }
    /// Whether the movie can be played (a browser that loaded it can).
    public static var isPlayable: AVAsyncProperty<AVAsset, Bool> { .init(key: "isPlayable") }
}

extension AVPartialAsyncProperty where Root == AVAssetTrack {
    public static var naturalSize: AVAsyncProperty<AVAssetTrack, CGSize> { .init(key: "naturalSize") }
    public static var isPlayable: AVAsyncProperty<AVAssetTrack, Bool> { .init(key: "isPlayable") }
    public static var isEnabled: AVAsyncProperty<AVAssetTrack, Bool> { .init(key: "isEnabled") }
}
