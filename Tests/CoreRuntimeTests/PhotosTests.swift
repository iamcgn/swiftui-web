// Photos and PhotosUI: the pickers over the runtime's file panel (IceCubes' and Mlem's
// photosPicker, GistHub's and Umbrella's PHPickerViewController), picker items that load as
// data and as an app's file representation, and the session's photo library (EhPanda's and
// Mlem's creation requests, OldOS's fetches and image requests).
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Photos
import PhotosUI
import AVFoundation

#if !os(WASI)
/// A 2 × 3 red PNG.
private let png = Data([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x02,
    0x00, 0x00, 0x00, 0x03, 0x08, 0x02, 0x00, 0x00, 0x00, 0x36, 0x88, 0x49, 0xD6, 0x00, 0x00, 0x00, 0x10, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x44, 0x0C, 0x28, 0x14, 0x00, 0x44, 0xD0, 0x05, 0xFB, 0xA4, 0xCF, 0xDE,
    0x80, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
])

@Observable
private final class PickerModel {
    var presented = false
    var item: PhotosPickerItem?
    var items: [PhotosPickerItem] = []
}

private struct SinglePicker: View {
    let model: PickerModel
    var body: some View {
        Color.clear.frame(width: 10, height: 10)
            .photosPicker(isPresented: Binding(get: { model.presented }, set: { model.presented = $0 }),
                          selection: Binding(get: { model.item }, set: { model.item = $0 }), matching: .images)
    }
}

private struct MultiplePicker: View {
    let model: PickerModel
    var body: some View {
        Color.clear.frame(width: 10, height: 10)
            .photosPicker(isPresented: Binding(get: { model.presented }, set: { model.presented = $0 }),
                          selection: Binding(get: { model.items }, set: { model.items = $0 }), maxSelectionCount: 2,
                          matching: .any(of: [.images, .videos]), photoLibrary: .shared())
    }
}

/// An app's movie, imported as a file (IceCubes' MovieFileTranseferable).
private struct Movie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { Movie(url: $0.file) }
    }
}

@Suite @MainActor struct PhotosPickerTests {
    private func run(_ runtime: Runtime) {
        for _ in 0..<3 { runtime.layout(in: CGSize(width: 100, height: 100)) }
    }

    @Test func singlePickerAsksForImagesAndLoadsTheChosenPhoto() async throws {
        let model = PickerModel()
        let runtime = Runtime()
        var requests: [HostFileOpenRequest] = []
        runtime.fileOpenHandler = { request, completion in
            requests.append(request)
            completion([HostFile(data: png, name: "red.png", mimeType: "image/png")])
        }
        runtime.mount(SinglePicker(model: model))
        run(runtime)
        #expect(requests.isEmpty)
        model.presented = true
        run(runtime)
        #expect(requests.count == 1 && requests[0].imagesOnly && !requests[0].allowsMultiple)
        #expect(!model.presented)
        let item = try #require(model.item)
        #expect(item.supportedContentTypes == [.png])
        #expect(try await item.loadTransferable(type: Data.self) == png)
        // The pick joins the session's library under the item's identifier.
        let id = try #require(item.itemIdentifier)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        #expect(assets.count == 1 && assets[0].mediaType == .image)
        #expect(assets[0].pixelWidth == 2 && assets[0].pixelHeight == 3)
        #expect(PhotosPickerItem(itemIdentifier: id) == item)
    }

    @Test func multiplePickerCapsTheSelectionAndLoadsAFileRepresentation() async throws {
        let model = PickerModel()
        let runtime = Runtime()
        var request: HostFileOpenRequest?
        runtime.fileOpenHandler = { asked, completion in
            request = asked
            completion([HostFile(data: Data([0, 0, 0, 24]), name: "clip.mp4", mimeType: "video/mp4"),
                        HostFile(data: png, name: "red.png", mimeType: "image/png"),
                        HostFile(data: png, name: "third.png", mimeType: "image/png")])
        }
        runtime.mount(MultiplePicker(model: model))
        run(runtime)
        model.presented = true
        run(runtime)
        #expect(request?.allowsMultiple == true && request?.imagesOnly == false)
        #expect(request?.extensions.contains("mp4") == true && request?.extensions.contains("png") == true)
        #expect(model.items.count == 2)
        #expect(model.items[0].supportedContentTypes == [.mpeg4Movie])
        let movie = try #require(try await model.items[0].loadTransferable(type: Movie.self))
        #expect(try Data(contentsOf: movie.url) == Data([0, 0, 0, 24]))
        #expect(movie.url.lastPathComponent == "clip.mp4")
        // A photo is not a movie.
        #expect(try await model.items[1].loadTransferable(type: Movie.self) == nil)
    }

    @Test func cancellingKeepsTheSelection() {
        let model = PickerModel()
        let runtime = Runtime()
        var answer: [HostFile] = [HostFile(data: png, name: "red.png", mimeType: "image/png")]
        runtime.fileOpenHandler = { _, completion in completion(answer) }
        runtime.mount(SinglePicker(model: model))
        run(runtime)
        model.presented = true
        run(runtime)
        let first = model.item
        #expect(first != nil)
        answer = []
        model.presented = true
        run(runtime)
        #expect(!model.presented && model.item == first)
    }

    @Test func filtersMapToThePanelsRequest() {
        #expect(PHPickerFilter._request(.images, allowsMultiple: false).imagesOnly)
        #expect(PHPickerFilter._request(.screenshots, allowsMultiple: false).imagesOnly)
        #expect(PHPickerFilter._request(.not(.videos), allowsMultiple: false).imagesOnly)
        let videos = PHPickerFilter._request(.videos, allowsMultiple: true)
        #expect(!videos.imagesOnly && videos.allowsMultiple && videos.extensions == ["mp4", "mov", "m4v"])
        let both = PHPickerFilter._request(nil, allowsMultiple: false)
        #expect(!both.imagesOnly && both.extensions.contains("heic") && both.extensions.contains("mov"))
        #expect(PHPickerFilter._request(.all(of: [.images, .not(.screenshots)]), allowsMultiple: false).imagesOnly)
    }

    @Test func pickerViewControllerHandsItsDelegateProviders() throws {
        final class Delegate: PHPickerViewControllerDelegate {
            var results: [[PHPickerResult]] = []
            func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { self.results.append(results) }
        }
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        let delegate = Delegate()
        picker.delegate = delegate
        let scene = UIKitScene.shared
        let previous = scene.fileOpenHandler
        defer { scene.fileOpenHandler = previous }
        var requests: [HostFileOpenRequest] = []
        scene.fileOpenHandler = { request, completion in
            requests.append(request)
            completion([HostFile(data: png, name: "red.png", mimeType: "image/png"), HostFile(data: png, name: "b.png", mimeType: "image/png")])
        }
        picker.viewDidAppear(false)
        picker.viewDidAppear(false)
        #expect(requests.count == 1 && requests[0].imagesOnly && !requests[0].allowsMultiple)
        #expect(delegate.results.count == 1 && delegate.results[0].count == 1)
        let result = try #require(delegate.results.first?.first)
        let id = try #require(result.assetIdentifier)
        #expect(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count == 1)
        #if !canImport(Darwin)
        #expect(result.itemProvider.canLoadObject(ofClass: UIImage.self))
        nonisolated(unsafe) var loaded: UIImage?
        result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in loaded = image as? UIImage }
        #expect(loaded?.size == CGSize(width: 2, height: 3))
        var data: Data?
        result.itemProvider.loadDataRepresentation(for: .image) { bytes, _ in data = bytes }
        #expect(data == png)
        #endif
    }
}

@Suite @MainActor struct PhotoLibraryTests {
    @Test func accessIsGranted() async {
        #expect(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        #expect(await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized)
        nonisolated(unsafe) var status: PHAuthorizationStatus?
        PHPhotoLibrary.requestAuthorization { answer in status = answer }
        #expect(status == .authorized)
    }

    @Test func creationRequestsSaveDownloadsAndJoinTheLibrary() async throws {
        var saved: [HostFile] = []
        _PhotoLibraryStore.saveHandler = { saved.append($0) }
        defer { _PhotoLibraryStore.saveHandler = nil }
        let photo = png
        nonisolated(unsafe) var identifier: String?
        try PHPhotoLibrary.shared().performChangesAndWait {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photo, options: nil)
            identifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        #expect(saved.count == 1 && saved[0].name == "Photo.png" && saved[0].mimeType == "image/png" && saved[0].data == png)
        let id = try #require(identifier)
        let asset = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject)
        #expect(asset.mediaType == .image && asset.pixelWidth == 2)

        var image: UIImage?
        PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: nil) { result, _ in
            image = result
        }
        #expect(image?.size == CGSize(width: 2, height: 3))
        var type: String?
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) { _, uti, _, _ in type = uti }
        #expect(type == "public.png")

        let video = FileManager.default.temporaryDirectory.appendingPathComponent("photos-test-clip.mov")
        try Data([1, 2, 3]).write(to: video)
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
        }
        #expect(saved.count == 2 && saved[1].name == "photos-test-clip.mov" && saved[1].mimeType == "video/quicktime")
        let videos = PHAsset.fetchAssets(with: .video, options: nil)
        #expect(videos.count >= 1)
        var item: AVPlayerItem?
        PHCachingImageManager().requestPlayerItem(forVideo: try #require(videos.lastObject), options: nil) { player, _ in item = player }
        #expect(item != nil)
    }

    @Test func imagesSaveAndFetchesSortNewestFirst() throws {
        var saved: [HostFile] = []
        _PhotoLibraryStore.saveHandler = { saved.append($0) }
        defer { _PhotoLibraryStore.saveHandler = nil }
        let image = try #require(UIImage(data: png))
        try PHPhotoLibrary.shared().performChangesAndWait {
            _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
        #expect(saved.map(\.name) == ["Photo.png"])
        let options = PHFetchOptions()
        #if canImport(Darwin)
        // Linux's Foundation sorts only by key paths to comparable values, which an asset's
        // optional dates are not.
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        #endif
        options.fetchLimit = 1
        let newest = PHAsset.fetchAssets(with: .image, options: options)
        #expect(newest.count == 1)
        var seen = 0
        newest.enumerateObjects { _, _, stop in seen += 1; stop.pointee = true }
        #expect(seen == 1)
    }
}
#endif
