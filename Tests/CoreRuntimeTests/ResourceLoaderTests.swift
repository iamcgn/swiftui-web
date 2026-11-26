// An asset whose URL the browser cannot load, with a resource loader's delegate that answers with
// the movie's bytes (Mlem's NukeVideo, which plays a downloaded clip from memory): the item, the
// asset's metadata read and the image generator all load the bytes from a URL the host makes for
// them, or a `data:` URL without a host. An asset at a web URL never asks its delegate, and a
// delegate that declines leaves the asset its own URL.
#if !os(WASI)
import AVFoundation
import AVCaptureHost
import Foundation
import Testing

private final class InMemory: NSObject, AVAssetResourceLoaderDelegate {
    let data: Data
    let type: String
    var asked = 0
    init(_ data: Data, type: String) { self.data = data; self.type = type }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        asked += 1
        if let content = loadingRequest.contentInformationRequest {
            content.contentType = type
            content.contentLength = Int64(data.count)
            content.isByteRangeAccessSupported = true
        }
        if let dataRequest = loadingRequest.dataRequest {
            #expect(dataRequest.requestsAllDataToEndOfResource && dataRequest.requestedOffset == 0)
            dataRequest.respond(with: data[Int(dataRequest.requestedOffset)...])
            #expect(dataRequest.currentOffset == Int64(data.count))
        }
        loadingRequest.finishLoading()
        return true
    }
}

@MainActor
private enum StandInHost {
    nonisolated(unsafe) static var made: [(Int, String)] = []
    nonisolated(unsafe) static var read: [String] = []
    static func install(_ url: String) {
        made = []
        read = []
        _AVFrameHost.objectURL = { bytes, mime in StandInHost.made.append((bytes.count, mime)); return url }
    }
}

private final class Declines: NSObject, AVAssetResourceLoaderDelegate {}

private final class DataAsset: AVURLAsset, @unchecked Sendable {
    let loader: InMemory
    init(_ data: Data) {
        loader = InMemory(data, type: AVFileType.mp4.rawValue)
        super.init(url: URL(string: "in-memory-data://clip")!, options: nil)
        resourceLoader.setDelegate(loader, queue: .global())
    }
}

@MainActor
@Suite(.serialized) struct ResourceLoaderTests {
    let bytes = Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70])

    @Test func theDelegatesBytesPlayFromTheHostsURL() {
        StandInHost.install("blob:https://app/1")
        defer { _AVFrameHost.objectURL = nil }
        let asset = DataAsset(bytes)
        let item = AVPlayerItem(asset: asset)
        #expect(item.url.absoluteString == "blob:https://app/1")
        #expect(asset.url.absoluteString == "in-memory-data://clip")
        let made = StandInHost.made
        #expect(made.count == 1 && made.first?.0 == bytes.count && made.first?.1 == "video/mp4")
        _ = AVPlayerItem(asset: asset)
        #expect(asset.loader.asked == 1 && StandInHost.made.count == 1)
    }

    @Test func withoutAHostTheBytesBecomeADataURL() {
        let asset = DataAsset(bytes)
        let url = AVPlayerItem(asset: asset).url.absoluteString
        #expect(url == "data:video/mp4;base64,\(bytes.base64EncodedString())")
    }

    @Test func theMetadataReadUsesTheAnsweredURL() async throws {
        StandInHost.install("blob:https://app/2")
        _AVFrameHost.info = { url, done in
            StandInHost.read.append(url)
            Task { @MainActor in done(_AVMovieInfo(duration: 3, width: 4, height: 3, hasAudio: false)) }
        }
        defer { _AVFrameHost.objectURL = nil; _AVFrameHost.info = nil }
        let duration = try await DataAsset(bytes).load(.duration)
        #expect(duration.seconds == 3 && StandInHost.read == ["blob:https://app/2"])
    }

    @Test func webURLsAndDecliningDelegatesKeepTheAssetsURL() {
        let web = AVURLAsset(url: URL(string: "https://example.com/clip.mp4")!)
        let loader = InMemory(bytes, type: "video/webm")
        web.resourceLoader.setDelegate(loader, queue: nil)
        #expect(AVPlayerItem(asset: web).url.absoluteString == "https://example.com/clip.mp4" && loader.asked == 0)
        #expect(web.resourceLoader.delegate === loader && web.resourceLoader.delegateQueue == nil)

        let declined = AVURLAsset(url: URL(string: "custom://clip")!)
        let declines = Declines()
        declined.resourceLoader.setDelegate(declines, queue: .main)
        #expect(AVPlayerItem(asset: declined).url.absoluteString == "custom://clip")
    }
}
#endif
