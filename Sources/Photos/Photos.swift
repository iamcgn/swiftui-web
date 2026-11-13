// The photo library (pf-small-frameworks): a web page cannot read the person's photos, so the
// library an app sees holds only what the app saved into it this session and what the person
// picked with PhotosUI's pickers. Access asked
// for is granted at once (there is no prompt to show), fetches return the saved assets, and a
// change block's creation requests save each photo or video as a download (the browser's
// downloads are where a page's "saved photos" go), keeping a copy in the session's library that
// `PHImageManager` reads back. PhotosUI's pickers bring photos in through the host's file panel.
#if os(WASI)
import WebFoundation
import WebCoreData      // NSPredicate and NSSortDescriptor, which Apple's Foundation declares
import WebImageIO       // CGImagePropertyOrientation
#else
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#endif
import SwiftUI          // UIKit, and the running app's runtime (its download for a save)
import CoreLocation
import AVFoundation

// MARK: - Authorization

/// Whether the app may read or add to the photo library.
public enum PHAuthorizationStatus: Int, Sendable {
    case notDetermined = 0, restricted, denied, authorized, limited
}

/// The access an app asks for: adding photos only, or reading and writing.
public enum PHAccessLevel: Int, Sendable {
    case addOnly = 1, readWrite = 2
}

// MARK: - Values

/// What an asset holds.
public enum PHAssetMediaType: Int, Sendable {
    case unknown = 0, image, video, audio
}

/// The kinds of photo and video an asset is.
public struct PHAssetMediaSubtype: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let photoPanorama = PHAssetMediaSubtype(rawValue: 1 << 0)
    public static let photoHDR = PHAssetMediaSubtype(rawValue: 1 << 1)
    public static let photoScreenshot = PHAssetMediaSubtype(rawValue: 1 << 2)
    public static let photoLive = PHAssetMediaSubtype(rawValue: 1 << 3)
    public static let photoDepthEffect = PHAssetMediaSubtype(rawValue: 1 << 4)
    public static let spatialMedia = PHAssetMediaSubtype(rawValue: 1 << 10)
    public static let videoStreamed = PHAssetMediaSubtype(rawValue: 1 << 16)
    public static let videoHighFrameRate = PHAssetMediaSubtype(rawValue: 1 << 17)
    public static let videoTimelapse = PHAssetMediaSubtype(rawValue: 1 << 18)
    public static let videoScreenRecording = PHAssetMediaSubtype(rawValue: 1 << 19)
    public static let videoCinematic = PHAssetMediaSubtype(rawValue: 1 << 21)
}

/// Where an asset came from.
public struct PHAssetSourceType: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let typeUserLibrary = PHAssetSourceType(rawValue: 1 << 0)
    public static let typeCloudShared = PHAssetSourceType(rawValue: 1 << 1)
    public static let typeiTunesSynced = PHAssetSourceType(rawValue: 1 << 2)
}

/// The kind of a resource added to a new asset.
public enum PHAssetResourceType: Int, Sendable {
    case photo = 1, video, audio, alternatePhoto, fullSizePhoto, fullSizeVideo, adjustmentData
    case adjustmentBasePhoto, pairedVideo, fullSizePairedVideo, adjustmentBasePairedVideo, adjustmentBaseVideo
    case photoProxy = 19
}

/// The edits an app may make to an asset.
public enum PHAssetEditOperation: Int, Sendable {
    case delete = 1, content, properties
}

// MARK: - Objects

/// A photo library object, known by its local identifier.
open class PHObject: NSObject, @unchecked Sendable {
    public let localIdentifier: String

    public override init() {
        localIdentifier = UUID().uuidString + "/L0/001"
        super.init()
    }

    package init(localIdentifier: String) {
        self.localIdentifier = localIdentifier
        super.init()
    }
}

/// Stands for an object a change block created, before the block ends.
open class PHObjectPlaceholder: PHObject, @unchecked Sendable {}

/// A photo or video in the library.
open class PHAsset: PHObject, @unchecked Sendable {
    open private(set) var mediaType: PHAssetMediaType = .unknown
    open private(set) var mediaSubtypes: PHAssetMediaSubtype = []
    open private(set) var pixelWidth = 0
    open private(set) var pixelHeight = 0
    open private(set) var creationDate: Date?
    open private(set) var modificationDate: Date?
    open private(set) var location: CLLocation?
    open private(set) var duration: TimeInterval = 0
    open private(set) var isFavorite = false
    open private(set) var isHidden = false
    open private(set) var sourceType: PHAssetSourceType = .typeUserLibrary
    open private(set) var burstIdentifier: String?
    open private(set) var representsBurst = false
    /// The asset's bytes, its content type and file name (saved this session).
    package private(set) var _resource: (data: Data, type: String, name: String)?

    public override init() { super.init() }

    package init(localIdentifier: String, mediaType: PHAssetMediaType, resource: (data: Data, type: String, name: String)?,
                 creationDate: Date?, location: CLLocation?, isFavorite: Bool, isHidden: Bool) {
        self.mediaType = mediaType
        _resource = resource
        self.creationDate = creationDate
        modificationDate = creationDate
        self.location = location
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        super.init(localIdentifier: localIdentifier)
        if let resource, mediaType == .image, let size = _PhotoLibraryStore.pixelSize(of: resource.data) {
            pixelWidth = size.width
            pixelHeight = size.height
        }
    }

    /// Whether the app may make the edit: every edit of an asset it saved.
    open func canPerform(_ editOperation: PHAssetEditOperation) -> Bool { _resource != nil }

    /// The library's assets the options select (those saved or picked this session).
    open class func fetchAssets(with options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        PHFetchResult(_PhotoLibraryStore.assets(where: { _ in true }, options: options))
    }

    /// The library's assets of the media type.
    open class func fetchAssets(with mediaType: PHAssetMediaType, options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        PHFetchResult(_PhotoLibraryStore.assets(where: { $0.mediaType == mediaType }, options: options))
    }

    /// The library's assets with the identifiers, in the order given.
    open class func fetchAssets(withLocalIdentifiers identifiers: [String], options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        let all = _PhotoLibraryStore.assets(where: { _ in true }, options: nil)
        let found = identifiers.compactMap { id in all.first { $0.localIdentifier == id } }
        return PHFetchResult(_PhotoLibraryStore.limited(found, options))
    }
}

// MARK: - Fetching

/// What a fetch selects and in what order. The library holds only the app's own saves, so a
/// predicate is not evaluated (every saved asset matches); sort descriptors on `creationDate`
/// or `modificationDate`, the fetch limit and hidden assets are honored.
open class PHFetchOptions: NSObject, @unchecked Sendable {
    open var predicate: NSPredicate?
    open var sortDescriptors: [NSSortDescriptor]?
    open var includeHiddenAssets = false
    open var includeAllBurstAssets = false
    open var includeAssetSourceTypes: PHAssetSourceType = []
    open var fetchLimit = 0
    open var wantsIncrementalChangeDetails = true
    public override init() { super.init() }
}

/// The objects a fetch returned, in order.
open class PHFetchResult<ObjectType: AnyObject>: NSObject, @unchecked Sendable {
    private let objects: [ObjectType]

    public override init() {
        objects = []
        super.init()
    }

    package init(_ objects: [ObjectType]) {
        self.objects = objects
        super.init()
    }

    open var count: Int { objects.count }
    open var firstObject: ObjectType? { objects.first }
    open var lastObject: ObjectType? { objects.last }
    open func object(at index: Int) -> ObjectType { objects[index] }
    open subscript(index: Int) -> ObjectType { objects[index] }
    open func objects(at indexes: IndexSet) -> [ObjectType] { indexes.map { objects[$0] } }
    open func contains(_ anObject: ObjectType) -> Bool { objects.contains { $0 === anObject } }
    open func index(of anObject: ObjectType) -> Int { objects.firstIndex { $0 === anObject } ?? NSNotFound }
    open func countOfAssets(with mediaType: PHAssetMediaType) -> Int {
        objects.reduce(0) { $0 + (($1 as? PHAsset)?.mediaType == mediaType ? 1 : 0) }
    }

    /// Runs `block` with each object and its index until the block sets its flag.
    open func enumerateObjects(_ block: (ObjectType, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop: ObjCBool = false
        for (index, object) in objects.enumerated() {
            block(object, index, &stop)
            if stop.boolValue { return }
        }
    }
}

// MARK: - The library

/// Told when the library's contents change.
public protocol PHPhotoLibraryChangeObserver: AnyObject {
    func photoLibraryDidChange(_ changeInstance: PHChange)
}

/// What a change block changed.
open class PHChange: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    /// The changes to a fetch's objects: none are tracked, so nil (refetch to see new saves).
    open func changeDetails<T: AnyObject>(for object: PHFetchResult<T>) -> PHFetchResultChangeDetails<T>? { nil }
}

/// The changes a change block made to a fetch's objects.
open class PHFetchResultChangeDetails<ObjectType: AnyObject>: NSObject, @unchecked Sendable {
    public let fetchResultBeforeChanges: PHFetchResult<ObjectType>
    public let fetchResultAfterChanges: PHFetchResult<ObjectType>
    open var hasIncrementalChanges: Bool { false }
    open var removedIndexes: IndexSet? { nil }
    open var insertedIndexes: IndexSet? { nil }
    open var changedIndexes: IndexSet? { nil }
    open var hasMoves: Bool { false }
    open var removedObjects: [ObjectType] { [] }
    open var insertedObjects: [ObjectType] { [] }
    open var changedObjects: [ObjectType] { [] }
    open func enumerateMoves(_ handler: (Int, Int) -> Void) {}

    public init(from before: PHFetchResult<ObjectType>, to after: PHFetchResult<ObjectType>) {
        fetchResultBeforeChanges = before
        fetchResultAfterChanges = after
        super.init()
    }
}

/// Why a change block could not save.
public struct PHPhotosError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Code: Int, Sendable {
        case internalError = -1, userCancelled = 3072, libraryVolumeOffline = 3114, relinquishingLibraryBundleToWriter = 3142
        case switchingSystemPhotoLibrary = 3143, networkAccessRequired = 3164, identifierNotFound = 3201
        case multipleIdentifiersFound = 3202, changeNotSupported = 3300, operationInterrupted = 3301
        case invalidResource = 3302, missingResource = 3303, notEnoughSpace = 3305, requestNotSupportedForAsset = 3306
        case accessRestricted = 3310, accessUserDenied = 3311, libraryInFileProviderSyncRoot = 3169
        case persistentChangeTokenExpired = 3105, persistentChangeDetailsUnavailable = 3210
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public var description: String { "PHPhotosError(\(code))" }
    public static let internalError = Code.internalError
    public static let invalidResource = Code.invalidResource
    public static let accessUserDenied = Code.accessUserDenied
}

/// The person's photo library, as the app sees it on the web: its own saves this session.
open class PHPhotoLibrary: NSObject, @unchecked Sendable {
    private static let library = PHPhotoLibrary()

    public override init() { super.init() }

    /// The shared library.
    open class func shared() -> PHPhotoLibrary { library }

    /// Authorized: there is no prompt on the web, and the library holds only the app's saves.
    open class func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    open class func authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus { .authorized }

    /// Grants access at once (the handler runs before the call returns).
    open class func requestAuthorization(_ handler: @escaping @Sendable (PHAuthorizationStatus) -> Void) {
        handler(.authorized)
    }
    open class func requestAuthorization(for accessLevel: PHAccessLevel, handler: @escaping @Sendable (PHAuthorizationStatus) -> Void) {
        handler(.authorized)
    }
    open class func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus { .authorized }

    /// Runs the change block, then saves what its requests created (a download for each new
    /// photo or video) and calls the handler.
    open func performChanges(_ changeBlock: @escaping @Sendable () -> Void, completionHandler: (@Sendable (Bool, (any Error)?) -> Void)? = nil) {
        Task { @MainActor in
            do {
                try PHPhotoLibrary._commit(changeBlock)
                completionHandler?(true, nil)
            } catch {
                completionHandler?(false, error)
            }
        }
    }

    /// Runs the change block and saves what its requests created.
    open func performChanges(_ changeBlock: @escaping @Sendable () -> Void) async throws {
        try await MainActor.run { try PHPhotoLibrary._commit(changeBlock) }
    }

    /// Runs the change block and saves what its requests created, before returning (on the
    /// page's one thread, which runs the app's main actor).
    open func performChangesAndWait(_ changeBlock: @Sendable () -> Void) throws {
        try MainActor.assumeIsolated { try PHPhotoLibrary._commit(changeBlock) }
    }

    open func register(_ observer: any PHPhotoLibraryChangeObserver) {
        observers.append(Weak(observer))
    }

    open func unregisterChangeObserver(_ observer: any PHPhotoLibraryChangeObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    private struct Weak { weak var value: (any PHPhotoLibraryChangeObserver)?; init(_ value: any PHPhotoLibraryChangeObserver) { self.value = value } }
    private var observers: [Weak] = []

    @MainActor
    private static func _commit(_ changeBlock: () -> Void) throws {
        _PhotoLibraryStore.pending = []
        changeBlock()
        let requests = _PhotoLibraryStore.pending
        _PhotoLibraryStore.pending = []
        guard !requests.isEmpty else { return }
        for request in requests {
            try request._commit()
        }
        let change = PHChange()
        for observer in library.observers { observer.value?.photoLibraryDidChange(change) }
    }
}

// MARK: - Change requests

/// A request, made inside a change block, to create or edit an asset.
open class PHAssetChangeRequest: NSObject, @unchecked Sendable {
    package var _resources: [(type: PHAssetResourceType, data: Data?, url: URL?, options: PHAssetResourceCreationOptions?)] = []
    package var _image: UIImage?
    package let _placeholder = PHObjectPlaceholder()
    package let _editing: PHAsset?
    open var creationDate: Date? = Date()
    open var location: CLLocation?
    open var isFavorite = false
    open var isHidden = false

    package init(_editing asset: PHAsset? = nil) {
        _editing = asset
        super.init()
        _PhotoLibraryStore.pending.append(self)
    }

    /// Edits an asset's properties (the dates, location and flags).
    public convenience init(for asset: PHAsset) {
        self.init(_editing: asset)
        creationDate = asset.creationDate
        location = asset.location
        isFavorite = asset.isFavorite
        isHidden = asset.isHidden
    }

    /// Creates an asset of the image.
    open class func creationRequestForAsset(from image: UIImage) -> PHAssetChangeRequest {
        let request = PHAssetChangeRequest()
        request._image = image
        return request
    }

    /// Creates an asset of the image file.
    open class func creationRequestForAssetFromImage(atFileURL fileURL: URL) -> PHAssetChangeRequest? {
        let request = PHAssetChangeRequest()
        request._resources.append((.photo, nil, fileURL, nil))
        return request
    }

    /// Creates an asset of the video file.
    open class func creationRequestForAssetFromVideo(atFileURL fileURL: URL) -> PHAssetChangeRequest? {
        let request = PHAssetChangeRequest()
        request._resources.append((.video, nil, fileURL, nil))
        return request
    }

    /// Stands for the created asset (its local identifier is the asset's).
    open var placeholderForCreatedAsset: PHObjectPlaceholder? { _editing == nil ? _placeholder : nil }

    /// Deletes the assets the app saved.
    open class func deleteAssets(_ assets: [PHAsset]) {
        _PhotoLibraryStore.deletions.append(contentsOf: assets.map(\.localIdentifier))
    }

    @MainActor
    package func _commit() throws {
        if !_PhotoLibraryStore.deletions.isEmpty {
            let doomed = Set(_PhotoLibraryStore.deletions)
            _PhotoLibraryStore.deletions = []
            _PhotoLibraryStore.saved.removeAll { doomed.contains($0.localIdentifier) }
        }
        if let asset = _editing {
            guard let index = _PhotoLibraryStore.saved.firstIndex(where: { $0 === asset }) else {
                throw PHPhotosError(.identifierNotFound)
            }
            let old = _PhotoLibraryStore.saved[index]
            _PhotoLibraryStore.saved[index] = PHAsset(localIdentifier: old.localIdentifier, mediaType: old.mediaType, resource: old._resource,
                                                      creationDate: creationDate, location: location, isFavorite: isFavorite, isHidden: isHidden)
            return
        }
        guard let resource = try _resource() else { return }
        let mediaType: PHAssetMediaType = resource.type.hasPrefix("video/") ? .video : resource.type.hasPrefix("audio/") ? .audio : .image
        let asset = PHAsset(localIdentifier: _placeholder.localIdentifier, mediaType: mediaType, resource: resource,
                            creationDate: creationDate, location: location, isFavorite: isFavorite, isHidden: isHidden)
        _PhotoLibraryStore.saved.append(asset)
        _PhotoLibraryStore.save(resource)
    }

    /// The new asset's main resource: the image, else the first resource's bytes.
    @MainActor
    private func _resource() throws -> (data: Data, type: String, name: String)? {
        if let image = _image {
            guard let data = image.jpegData(compressionQuality: 1) else { throw PHPhotosError(.invalidResource) }
            let type = _PhotoLibraryStore.imageType(of: data)
            return (data, type, "Photo." + (type == "image/png" ? "png" : "jpg"))
        }
        guard let first = _resources.first(where: { $0.type != .adjustmentData }) ?? _resources.first else { return nil }
        let data: Data
        if let bytes = first.data {
            data = bytes
        } else if let url = first.url, let bytes = try? Data(contentsOf: url) {
            data = bytes
        } else {
            throw PHPhotosError(.invalidResource)
        }
        let name = first.options?.originalFilename ?? first.url?.lastPathComponent
        let type = _PhotoLibraryStore.mimeType(for: name, data: data, video: first.type == .video || first.type == .fullSizeVideo || first.type == .pairedVideo)
        let fallback = type.hasPrefix("video/") ? "Video.mp4" : "Photo." + (type == "image/png" ? "png" : "jpg")
        return (data, type, name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback)
    }
}

/// A request to create an asset from resources (a photo's data, a video file).
open class PHAssetCreationRequest: PHAssetChangeRequest, @unchecked Sendable {
    /// A request for a new asset, to add resources to.
    open class func forAsset() -> PHAssetCreationRequest { PHAssetCreationRequest(_editing: nil) }

    /// Whether the resource types make an asset: a photo or a video first.
    open class func supportsAssetResourceTypes(_ types: [Int]) -> Bool {
        types.first.flatMap(PHAssetResourceType.init(rawValue:)).map { [.photo, .video, .fullSizePhoto, .fullSizeVideo].contains($0) } ?? false
    }

    open func addResource(with type: PHAssetResourceType, fileURL: URL, options: PHAssetResourceCreationOptions?) {
        _resources.append((type, nil, fileURL, options))
    }

    open func addResource(with type: PHAssetResourceType, data: Data, options: PHAssetResourceCreationOptions?) {
        _resources.append((type, data, nil, options))
    }
}

/// How an added resource is named and typed.
open class PHAssetResourceCreationOptions: NSObject, @unchecked Sendable {
    open var originalFilename: String?
    open var uniformTypeIdentifier: String?
    open var shouldMoveFile = false
    public override init() { super.init() }
}

// MARK: - Images

/// How an image fits the requested size.
public enum PHImageContentMode: Int, Sendable {
    case aspectFit = 0, aspectFill = 1
    public static let `default` = PHImageContentMode.aspectFit
}

public typealias PHImageRequestID = Int32
public let PHInvalidImageRequestID: PHImageRequestID = 0
/// The size that asks for an asset's full-size image.
public let PHImageManagerMaximumSize = CGSize(width: -1, height: -1)
public let PHImageResultIsInCloudKey = "PHImageResultIsInCloudKey"
public let PHImageResultIsDegradedKey = "PHImageResultIsDegradedKey"
public let PHImageResultRequestIDKey = "PHImageResultRequestIDKey"
public let PHImageCancelledKey = "PHImageCancelledKey"
public let PHImageErrorKey = "PHImageErrorKey"

/// Which version of an asset's image to deliver.
public enum PHImageRequestOptionsVersion: Int, Sendable {
    case current = 0, unadjusted, original
}

/// How quickly, and how good, the delivered image is.
public enum PHImageRequestOptionsDeliveryMode: Int, Sendable {
    case opportunistic = 0, highQualityFormat, fastFormat
}

/// How the delivered image is resized.
public enum PHImageRequestOptionsResizeMode: Int, Sendable {
    case none = 0, fast, exact
}

/// Options for an image request.
open class PHImageRequestOptions: NSObject, @unchecked Sendable {
    open var version: PHImageRequestOptionsVersion = .current
    open var deliveryMode: PHImageRequestOptionsDeliveryMode = .opportunistic
    open var resizeMode: PHImageRequestOptionsResizeMode = .fast
    open var normalizedCropRect: CGRect = .zero
    open var isNetworkAccessAllowed = false
    open var isSynchronous = false
    open var allowSecondaryDegradedImage = false
    open var progressHandler: ((Double, (any Error)?, UnsafeMutablePointer<ObjCBool>, [AnyHashable: Any]?) -> Void)?
    public override init() { super.init() }
}

/// Which version of a video to deliver.
public enum PHVideoRequestOptionsVersion: Int, Sendable { case current = 0, original }
/// The quality of a delivered video.
public enum PHVideoRequestOptionsDeliveryMode: Int, Sendable { case automatic = 0, highQualityFormat, mediumQualityFormat, fastFormat }

/// Options for a video request.
open class PHVideoRequestOptions: NSObject, @unchecked Sendable {
    open var version: PHVideoRequestOptionsVersion = .current
    open var deliveryMode: PHVideoRequestOptionsDeliveryMode = .automatic
    open var isNetworkAccessAllowed = false
    open var progressHandler: ((Double, (any Error)?, UnsafeMutablePointer<ObjCBool>, [AnyHashable: Any]?) -> Void)?
    public override init() { super.init() }
}

/// Delivers assets' images and data: an asset the app saved has its bytes; another has none.
open class PHImageManager: NSObject, @unchecked Sendable {
    private static let shared = PHImageManager()
    private var nextID: PHImageRequestID = 1

    public override init() { super.init() }

    open class func `default`() -> PHImageManager { shared }

    /// The asset's image (its full image, which views scale), delivered before the call returns.
    @discardableResult
    open func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, options: PHImageRequestOptions?,
                           resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        let id = issue()
        let image = asset.mediaType == .image ? asset._resource.flatMap { UIImage(data: $0.data) } : nil
        var info: [AnyHashable: Any] = [PHImageResultRequestIDKey: id, PHImageResultIsDegradedKey: false, PHImageResultIsInCloudKey: false]
        if image == nil { info[PHImageErrorKey] = PHPhotosError(.missingResource) }
        resultHandler(image, info)
        return id
    }

    /// The asset's image bytes, their type identifier and orientation, delivered at once.
    @discardableResult
    open func requestImageDataAndOrientation(for asset: PHAsset, options: PHImageRequestOptions?,
                                             resultHandler: @escaping (Data?, String?, CGImagePropertyOrientation, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        let id = issue()
        let resource = asset.mediaType == .image ? asset._resource : nil
        var info: [AnyHashable: Any] = [PHImageResultRequestIDKey: id, PHImageResultIsInCloudKey: false]
        if resource == nil { info[PHImageErrorKey] = PHPhotosError(.missingResource) }
        resultHandler(resource?.data, resource.map { _PhotoLibraryStore.typeIdentifier(forMIME: $0.type) }, .up, info)
        return id
    }

    /// A player item for the video asset (a saved video's file), delivered at once.
    @discardableResult
    open func requestPlayerItem(forVideo asset: PHAsset, options: PHVideoRequestOptions?,
                                resultHandler: @escaping (AVPlayerItem?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        let id = issue()
        resultHandler(_PhotoLibraryStore.videoURL(of: asset).map(AVPlayerItem.init(url:)), [PHImageResultRequestIDKey: id])
        return id
    }

    /// Cancels a request (every request has already been delivered).
    open func cancelImageRequest(_ requestID: PHImageRequestID) {}

    private func issue() -> PHImageRequestID {
        defer { nextID &+= 1 }
        return nextID
    }
}

/// An image manager that prepares images ahead (there is nothing to prepare: the saved images
/// are already in memory).
open class PHCachingImageManager: PHImageManager, @unchecked Sendable {
    open var allowsCachingHighQualityImages = true
    public override init() { super.init() }
    open func startCachingImages(for assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode, options: PHImageRequestOptions?) {}
    open func stopCachingImages(for assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode, options: PHImageRequestOptions?) {}
    open func stopCachingImagesForAllAssets() {}
}

#if !canImport(ImageIO) && !os(WASI)
/// EXIF orientations, as ImageIO names them (Linux has no ImageIO).
public enum CGImagePropertyOrientation: UInt32, Sendable {
    case up = 1, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left
}
#endif

// MARK: - The session's library

/// The assets the app saved this session, and the requests of the change block that runs.
package enum _PhotoLibraryStore {
    nonisolated(unsafe) package static var saved: [PHAsset] = []
    nonisolated(unsafe) static var pending: [PHAssetChangeRequest] = []
    nonisolated(unsafe) static var deletions: [String] = []
    /// Where a saved photo or video goes: the host's download, else the UIKit scene's saver.
    nonisolated(unsafe) package static var saveHandler: (@MainActor (HostFile) -> Void)?

    static func assets(where include: (PHAsset) -> Bool, options: PHFetchOptions?) -> [PHAsset] {
        var found = saved.filter { include($0) && (options?.includeHiddenAssets == true || !$0.isHidden) }
        for descriptor in (options?.sortDescriptors ?? []).reversed() {
            guard let key = sortKey(descriptor), key == "creationDate" || key == "modificationDate" else { continue }
            let ascending = descriptor.ascending
            found.sort { a, b in
                let x = (key == "creationDate" ? a.creationDate : a.modificationDate) ?? .distantPast
                let y = (key == "creationDate" ? b.creationDate : b.modificationDate) ?? .distantPast
                return ascending ? x < y : x > y
            }
        }
        return limited(found, options)
    }

    /// The descriptor's key: its name, or on Linux (whose Foundation has no key-value coding)
    /// the name of the asset date its key path reads.
    static func sortKey(_ descriptor: NSSortDescriptor) -> String? {
        #if canImport(Darwin) || os(WASI)
        return descriptor.key
        #else
        if descriptor.keyPath == \PHAsset.creationDate { return "creationDate" }
        if descriptor.keyPath == \PHAsset.modificationDate { return "modificationDate" }
        return nil
        #endif
    }

    static func limited(_ assets: [PHAsset], _ options: PHFetchOptions?) -> [PHAsset] {
        guard let limit = options?.fetchLimit, limit > 0, assets.count > limit else { return assets }
        return Array(assets.prefix(limit))
    }

    /// A photo or video the person picked (PhotosUI's pickers): an asset of the session's
    /// library, so fetching its identifier finds it. It is not saved again.
    package static func register(picked data: Data, type: String, name: String) -> PHAsset {
        let mediaType: PHAssetMediaType = type.hasPrefix("video/") ? .video : type.hasPrefix("audio/") ? .audio : .image
        let asset = PHAsset(localIdentifier: UUID().uuidString + "/L0/001", mediaType: mediaType, resource: (data, type, name),
                            creationDate: Date(), location: nil, isFavorite: false, isHidden: false)
        saved.append(asset)
        return asset
    }

    /// The asset with the identifier, if the session's library has it.
    package static func asset(identifier: String) -> PHAsset? { saved.first { $0.localIdentifier == identifier } }

    @MainActor
    static func save(_ resource: (data: Data, type: String, name: String)) {
        let file = HostFile(data: resource.data, name: resource.name, mimeType: resource.type)
        if let handler = saveHandler { handler(file); return }
        (UIKitScene.shared.fileSaveHandler ?? _appRemount?.runtime.fileSaveHandler)?(file)
    }

    /// A saved video's bytes as a file the player reads.
    static func videoURL(of asset: PHAsset) -> URL? {
        guard asset.mediaType == .video, let resource = asset._resource else { return nil }
        return _TransferItem.storeFile(resource.data, name: resource.name)
    }

    /// PNG or JPEG, by the bytes' signature.
    static func imageType(of data: Data) -> String {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
    }

    /// A file's MIME type, by its extension, else by its bytes.
    static func mimeType(for name: String?, data: Data, video: Bool) -> String {
        let ext = name.flatMap { $0.split(separator: ".").last.map { $0.lowercased() } } ?? ""
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "webp": return "image/webp"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        default:
            if video { return "video/mp4" }
            if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
            return imageType(of: data)
        }
    }

    /// The uniform type identifier for a MIME type.
    static func typeIdentifier(forMIME mime: String) -> String {
        switch mime {
        case "image/png": return "public.png"
        case "image/jpeg": return "public.jpeg"
        case "image/gif": return "com.compuserve.gif"
        case "image/heic": return "public.heic"
        case "image/webp": return "org.webmproject.webp"
        case "video/mp4": return "public.mpeg-4"
        case "video/quicktime": return "com.apple.quicktime-movie"
        default: return "public.data"
        }
    }

    /// A PNG's or JPEG's pixel size, from its header.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data.prefix(64 * 1024))
        if bytes.count >= 24, bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            func be32(_ i: Int) -> Int { Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]) }
            return (be32(16), be32(20))
        }
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                let height = Int(bytes[i + 5]) << 8 | Int(bytes[i + 6])
                let width = Int(bytes[i + 7]) << 8 | Int(bytes[i + 8])
                return (width, height)
            }
            i += 2 + length
        }
        return nil
    }
}
