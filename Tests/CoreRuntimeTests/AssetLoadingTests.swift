// A movie's asset loading (AVFoundation's `load(_:)` and `loadTracks(withMediaType:)`) over a
// stand-in for the browser's `<video>` metadata, and the seeking and queue players a video view
// drives: what Mlem's video view calls. The movie's length, picture and sound come from one read
// of the host per asset; sound the browser does not report is taken to be there; without a host
// or for a movie that fails to load, loading throws; an item keeps where it was sought to; and a
// queue player made from one item queues that item.
#if !os(WASI)
import AVFoundation
import AVCaptureHost
import Foundation
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
private enum StandInMetadata {
    nonisolated(unsafe) static var reads: [String] = []

    static func install(_ info: _AVMovieInfo?) {
        reads = []
        _AVFrameHost.info = { url, done in
            StandInMetadata.reads.append(url)
            Task { @MainActor in done(info) }
        }
    }
}

@MainActor
@Suite(.serialized) struct AssetLoadingTests {
    let movie = URL(string: "https://example.com/clip.mp4")!

    @Test func durationAndTracksComeFromOneRead() async throws {
        StandInMetadata.install(_AVMovieInfo(duration: 12.5, width: 640, height: 360, hasAudio: false))
        defer { _AVFrameHost.info = nil }
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration)
        #expect(duration.seconds == 12.5)
        #expect(duration.timescale == 600)
        #expect(duration.value == 7500)
        let video = try await asset.loadTracks(withMediaType: .video)
        #expect(video.count == 1)
        #expect(video.first?.naturalSize == CGSize(width: 640, height: 360))
        #expect(try await video[0].load(.naturalSize) == CGSize(width: 640, height: 360))
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let (length, playable) = try await asset.load(.duration, .isPlayable)
        #expect(length == duration)
        #expect(playable)
        // The item a player is made from keeps the same asset, so it is not read again.
        let item = AVPlayerItem(asset: asset)
        #expect(try await item.asset.load(.tracks).count == 1)
        #expect(StandInMetadata.reads == [movie.absoluteString])
    }

    @Test func soundTheBrowserDoesNotReportIsTakenToBeThere() async throws {
        StandInMetadata.install(_AVMovieInfo(duration: .infinity, width: 0, height: 0, hasAudio: nil))
        defer { _AVFrameHost.info = nil }
        let asset = AVURLAsset(url: movie)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(try await asset.load(.duration) == .indefinite)
    }

    @Test func aMovieThatFailsToLoadThrows() async {
        StandInMetadata.install(nil)
        defer { _AVFrameHost.info = nil }
        await #expect(throws: AVError.self) { try await AVURLAsset(url: movie).load(.duration) }
        _AVFrameHost.info = nil
        await #expect(throws: AVError.self) { try await AVURLAsset(url: movie).loadTracks(withMediaType: .audio) }
    }

    @Test func itemsKeepWhereTheyWereSoughtTo() {
        let item = AVPlayerItem(url: movie)
        #expect(item.currentTime() == .zero)
        item.seek(to: CMTime(seconds: 4, preferredTimescale: 30), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
        #expect(item.currentTime().seconds == 4)
        let player: AVQueuePlayer = .init(playerItem: item)
        #expect(player.items.count == 1)
        #expect(player.currentTime().seconds == 4)
        player.seek(to: CMTime(value: 3, timescale: 2))
        #expect(item.currentTime().seconds == 1.5)
        #expect(CMTime(value: 1, timescale: 2) == CMTime(seconds: 0.5, preferredTimescale: 600))
        #expect(CMTime.invalid == CMTime.invalid)
    }
}
#endif
