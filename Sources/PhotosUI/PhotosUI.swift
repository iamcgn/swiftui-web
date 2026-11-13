// The photo pickers (pf-small-frameworks): `PhotosPicker`, `photosPicker` and
// `PHPickerViewController` open the host's file panel for photos or videos (a browser's file
// input, which on a phone offers the photo library and camera), and hand back what the person
// chose as picker items or item providers that load it. Each pick also joins the session's
// photo library (Photos), so an app that fetches a picked item's identifier finds its asset.
import SwiftUI
import Photos

// MARK: - Filters

/// Which assets a picker offers.
public struct PHPickerFilter: Hashable, Sendable {
    indirect enum Kind: Hashable, Sendable {
        case images, videos, livePhotos, depthEffectPhotos, bursts, panoramas, screenshots, screenRecordings
        case cinematicVideos, slomoVideos, timelapseVideos, spatialMedia
        case any([PHPickerFilter]), all([PHPickerFilter]), not(PHPickerFilter)
    }
    let kind: Kind

    public static let images = PHPickerFilter(kind: .images)
    public static let videos = PHPickerFilter(kind: .videos)
    public static let livePhotos = PHPickerFilter(kind: .livePhotos)
    public static let depthEffectPhotos = PHPickerFilter(kind: .depthEffectPhotos)
    public static let bursts = PHPickerFilter(kind: .bursts)
    public static let panoramas = PHPickerFilter(kind: .panoramas)
    public static let screenshots = PHPickerFilter(kind: .screenshots)
    public static let screenRecordings = PHPickerFilter(kind: .screenRecordings)
    public static let cinematicVideos = PHPickerFilter(kind: .cinematicVideos)
    public static let slomoVideos = PHPickerFilter(kind: .slomoVideos)
    public static let timelapseVideos = PHPickerFilter(kind: .timelapseVideos)
    public static let spatialMedia = PHPickerFilter(kind: .spatialMedia)

    /// Assets any of the filters offers.
    public static func any(of subfilters: [PHPickerFilter]) -> PHPickerFilter { PHPickerFilter(kind: .any(subfilters)) }
    /// Assets every filter offers.
    public static func all(of subfilters: [PHPickerFilter]) -> PHPickerFilter { PHPickerFilter(kind: .all(subfilters)) }
    /// Assets the filter does not offer.
    public static func not(_ filter: PHPickerFilter) -> PHPickerFilter { PHPickerFilter(kind: .not(filter)) }

    /// Whether the filter offers photos and videos: what a file panel can tell apart (a
    /// screenshot or a live photo is a photo to it).
    package var _accepts: (images: Bool, videos: Bool) {
        switch kind {
        case .images, .livePhotos, .depthEffectPhotos, .bursts, .panoramas, .screenshots, .spatialMedia: return (true, false)
        case .videos, .screenRecordings, .cinematicVideos, .slomoVideos, .timelapseVideos: return (false, true)
        case .any(let filters): return filters.reduce((false, false)) { ($0.0 || $1._accepts.images, $0.1 || $1._accepts.videos) }
        case .all(let filters): return filters.reduce((true, true)) { ($0.0 && $1._accepts.images, $0.1 && $1._accepts.videos) }
        case .not(let filter):
            // Only "not photos" and "not videos" rule a whole kind out.
            switch filter.kind {
            case .images: return (false, true)
            case .videos: return (true, false)
            default: return (true, true)
            }
        }
    }

    /// The host's open panel for what the filter offers (photos and videos when none, or when
    /// it offers nothing a panel can tell apart).
    package static func _request(_ filter: PHPickerFilter?, allowsMultiple: Bool) -> HostFileOpenRequest {
        let accepts = filter?._accepts ?? (false, false)
        switch (accepts.images, accepts.videos) {
        case (true, false): return HostFileOpenRequest(extensions: [], allowsMultiple: allowsMultiple, imagesOnly: true)
        case (false, true): return HostFileOpenRequest(extensions: _videoExtensions, allowsMultiple: allowsMultiple)
        default: return HostFileOpenRequest(extensions: _imageExtensions + _videoExtensions, allowsMultiple: allowsMultiple)
        }
    }
}

let _imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp"]
let _videoExtensions = ["mp4", "mov", "m4v"]

/// A picked file's content type: its MIME type's, else its extension's.
func _contentType(of file: HostFile) -> UTType {
    if let type = UTType(mimeType: file.mimeType), type != .data { return type }
    let ext = file.name.split(separator: ".").last.map { $0.lowercased() } ?? ""
    let known: [String: UTType] = ["gif": .gif, "heic": .heic, "heif": .heic, "webp": .webP, "mp4": .mpeg4Movie,
                                   "m4v": .mpeg4Movie, "mov": .quickTimeMovie]
    return known[ext] ?? UTType(filenameExtension: ext) ?? .data
}

/// A picked file as an asset of the session's library.
@MainActor
func _register(_ file: HostFile) -> (asset: PHAsset, type: UTType) {
    let type = _contentType(of: file)
    let mime = type.preferredMIMEType ?? file.mimeType
    return (_PhotoLibraryStore.register(picked: file.data, type: mime, name: file.name), type)
}

// MARK: - Picker items

/// A photo or video the person chose in a `PhotosPicker`, which loads as a transferable value.
public struct PhotosPickerItem: Hashable, Sendable {
    /// Which encoding of an asset to load when it has more than one.
    public struct EncodingDisambiguationPolicy: Hashable, Sendable {
        let tag: UInt8
        /// The best encoding for the app (the file as picked).
        public static let automatic = EncodingDisambiguationPolicy(tag: 0)
        /// The asset's current encoding.
        public static let current = EncodingDisambiguationPolicy(tag: 1)
        /// The most compatible encoding (JPEG, H.264).
        public static let compatible = EncodingDisambiguationPolicy(tag: 2)
    }

    /// The asset's local identifier in the photo library.
    public let itemIdentifier: String?
    /// The types the item loads as.
    public let supportedContentTypes: [UTType]
    private let file: _PickedFile?

    /// The item for an asset of the library (one saved or picked this session loads its bytes).
    public init(itemIdentifier: String) {
        self.itemIdentifier = itemIdentifier
        if let asset = _PhotoLibraryStore.asset(identifier: itemIdentifier), let resource = asset._resource {
            let type = UTType(mimeType: resource.type) ?? .data
            file = _PickedFile(data: resource.data, name: resource.name, type: type)
            supportedContentTypes = [type]
        } else {
            file = nil
            supportedContentTypes = []
        }
    }

    /// The item for an asset of the library, loaded in the encoding the policy picks.
    public init(itemIdentifier: String, preferredItemEncoding: EncodingDisambiguationPolicy) {
        self.init(itemIdentifier: itemIdentifier)
    }

    @MainActor
    package init(_picked file: HostFile) {
        let (asset, type) = _register(file)
        itemIdentifier = asset.localIdentifier
        self.file = _PickedFile(data: file.data, name: file.name, type: type)
        supportedContentTypes = [type]
    }

    /// The item as `T`: the bytes as `Data`, or one of `T`'s importers fed the file (a photo
    /// representation, a file representation the importer reads from a URL). Nil when `T`
    /// imports none of the item's types.
    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
        _load(T.self)
    }

    /// Loads the item as `T`; the handler runs before the call returns.
    @discardableResult
    public func loadTransferable<T: Transferable>(type: T.Type, completionHandler: @escaping @Sendable (Result<T?, any Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler(.success(_load(T.self)))
        progress.completedUnitCount = 1
        return progress
    }

    private func _load<T: Transferable>(_ type: T.Type) -> T? {
        guard let file else { return nil }
        let item = ExternalDragItem(type: file.type.identifier, data: file.data, fileName: file.name)
        return _TransferItem(external: [item]).load(as: T.self)
    }

    public static func == (lhs: PhotosPickerItem, rhs: PhotosPickerItem) -> Bool {
        lhs.itemIdentifier == rhs.itemIdentifier && lhs.supportedContentTypes == rhs.supportedContentTypes
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(itemIdentifier) }
}

/// A picked file's bytes (a class, so items stay cheap to copy and compare).
final class _PickedFile: Sendable {
    let data: Data
    let name: String
    let type: UTType
    init(data: Data, name: String, type: UTType) {
        self.data = data
        self.name = name
        self.type = type
    }
}

/// How a picker that takes several items adds to the selection.
public struct PhotosPickerSelectionBehavior: Hashable, Sendable {
    let tag: UInt8
    public static let `default` = PhotosPickerSelectionBehavior(tag: 0)
    public static let ordered = PhotosPickerSelectionBehavior(tag: 1)
    public static let continuous = PhotosPickerSelectionBehavior(tag: 2)
    public static let continuousAndOrdered = PhotosPickerSelectionBehavior(tag: 3)
}

/// How a picker shows: the host's panel takes the whole screen in each style.
public struct PhotosPickerStyle: Hashable, Sendable {
    let tag: UInt8
    public static let presentation = PhotosPickerStyle(tag: 0)
    public static let inline = PhotosPickerStyle(tag: 1)
    public static let compact = PhotosPickerStyle(tag: 2)
}

/// The picker features an app turns off (the host's panel has none of them).
public struct PHPickerCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let search = PHPickerCapabilities(rawValue: 1 << 0)
    public static let stagingArea = PHPickerCapabilities(rawValue: 1 << 1)
    public static let collectionNavigation = PHPickerCapabilities(rawValue: 1 << 2)
    public static let selectionActions = PHPickerCapabilities(rawValue: 1 << 3)
    public static let sensitivityAnalysisIntervention = PHPickerCapabilities(rawValue: 1 << 4)
}

// MARK: - The modifier

/// Hands the chosen items to the selection (a class so the runtime's field reflection ignores it).
final class _PhotosDelivery {
    let deliver: ([PhotosPickerItem]) -> Void
    init(_ deliver: @escaping ([PhotosPickerItem]) -> Void) { self.deliver = deliver }
}

/// `photosPicker`: when the binding turns true, the host's open panel for the filter's photos
/// or videos; the chosen files become the selection (at most `limit` of them, 0 for any
/// number). The binding is reset when the panel closes; closing it without a choice keeps the
/// selection.
struct _PhotosPickerModifier {
    let isPresented: Binding<Bool>
    let filter: PHPickerFilter?
    let limit: Int
    let delivery: _PhotosDelivery
}

extension _PhotosPickerModifier: ViewModifier {
    func body(content: Content) -> some View {
        let isPresented = self.isPresented, filter = self.filter, limit = self.limit, delivery = self.delivery
        return _FileDialogTrigger(content: content, isPresented: isPresented, present: _FileDialogPresenter { runtime in
            _PhotosPickerModifier.present(isPresented: isPresented, filter: filter, limit: limit, delivery: delivery, runtime: runtime)
        })
    }

    @MainActor
    static func present(isPresented: Binding<Bool>, filter: PHPickerFilter?, limit: Int, delivery: _PhotosDelivery, runtime: Runtime?) {
        guard let open = runtime?.fileOpenHandler ?? UIKitScene.shared.fileOpenHandler else {
            isPresented.wrappedValue = false
            return
        }
        open(PHPickerFilter._request(filter, allowsMultiple: limit != 1)) { files in
            isPresented.wrappedValue = false
            guard !files.isEmpty else { return }
            let chosen = limit > 0 ? Array(files.prefix(limit)) : files
            delivery.deliver(chosen.map { PhotosPickerItem(_picked: $0) })
        }
    }
}

extension View {
    /// Presents the photo picker for one item when `isPresented` turns true.
    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        modifier(_PhotosPickerModifier(isPresented: isPresented, filter: filter, limit: 1,
                                       delivery: _PhotosDelivery { selection.wrappedValue = $0.first }))
    }

    /// Presents the photo picker for one item of the library when `isPresented` turns true.
    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                                         photoLibrary: PHPhotoLibrary) -> some View {
        photosPicker(isPresented: isPresented, selection: selection, matching: filter, preferredItemEncoding: preferredItemEncoding)
    }

    /// Presents the photo picker for up to `maxSelectionCount` items (any number when nil).
    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                                         selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        modifier(_PhotosPickerModifier(isPresented: isPresented, filter: filter, limit: max(maxSelectionCount ?? 0, 0),
                                       delivery: _PhotosDelivery { selection.wrappedValue = $0 }))
    }

    /// Presents the photo picker for up to `maxSelectionCount` items of the library.
    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                                         selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                                         photoLibrary: PHPhotoLibrary) -> some View {
        photosPicker(isPresented: isPresented, selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior,
                     matching: filter, preferredItemEncoding: preferredItemEncoding)
    }

    /// Sets how the pickers in this view show (the host's panel shows the same in each style).
    nonisolated public func photosPickerStyle(_ style: PhotosPickerStyle) -> some View { self }

    /// Turns off picker features (the host's panel has none of them).
    nonisolated public func photosPickerDisabledCapabilities(_ disabledCapabilities: PHPickerCapabilities) -> some View { self }

    /// Shows or hides the picker's accessories (the host's panel has none).
    nonisolated public func photosPickerAccessoryVisibility(_ visibility: Visibility, edges: Edge.Set = .all) -> some View { self }
}

// MARK: - PhotosPicker

/// A button that presents the photo picker.
public struct PhotosPicker<Label: View>: View {
    private let label: Label
    private let filter: PHPickerFilter?
    private let limit: Int
    private let delivery: _PhotosDelivery
    @State private var isPresented = false

    private init(filter: PHPickerFilter?, limit: Int, delivery: _PhotosDelivery, label: Label) {
        self.filter = filter
        self.limit = limit
        self.delivery = delivery
        self.label = label
    }

    /// A picker for one item.
    public init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic, @ViewBuilder label: () -> Label) {
        self.init(filter: filter, limit: 1, delivery: _PhotosDelivery { selection.wrappedValue = $0.first }, label: label())
    }

    /// A picker for one item of the library.
    public init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic, photoLibrary: PHPhotoLibrary,
                @ViewBuilder label: () -> Label) {
        self.init(selection: selection, matching: filter, preferredItemEncoding: preferredItemEncoding, label: label)
    }

    /// A picker for up to `maxSelectionCount` items (any number when nil).
    public init(selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil, selectionBehavior: PhotosPickerSelectionBehavior = .default,
                matching filter: PHPickerFilter? = nil, preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                @ViewBuilder label: () -> Label) {
        self.init(filter: filter, limit: max(maxSelectionCount ?? 0, 0), delivery: _PhotosDelivery { selection.wrappedValue = $0 }, label: label())
    }

    /// A picker for up to `maxSelectionCount` items of the library.
    public init(selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil, selectionBehavior: PhotosPickerSelectionBehavior = .default,
                matching filter: PHPickerFilter? = nil, preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                photoLibrary: PHPhotoLibrary, @ViewBuilder label: () -> Label) {
        self.init(selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior, matching: filter,
                  preferredItemEncoding: preferredItemEncoding, label: label)
    }

    public var body: some View {
        Button { isPresented = true } label: { label }
            .modifier(_PhotosPickerModifier(isPresented: $isPresented, filter: filter, limit: limit, delivery: delivery))
    }
}

extension PhotosPicker where Label == Text {
    /// A picker for one item, titled with a localized key.
    public init(_ titleKey: LocalizedStringKey, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        self.init(selection: selection, matching: filter, preferredItemEncoding: preferredItemEncoding) { Text(titleKey) }
    }

    /// A picker for one item, titled with a string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                   preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        self.init(selection: selection, matching: filter, preferredItemEncoding: preferredItemEncoding) { Text(title) }
    }

    /// A picker for one item of the library, titled with a localized key.
    public init(_ titleKey: LocalizedStringKey, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic, photoLibrary: PHPhotoLibrary) {
        self.init(selection: selection, matching: filter, preferredItemEncoding: preferredItemEncoding) { Text(titleKey) }
    }

    /// A picker for several items, titled with a localized key.
    public init(_ titleKey: LocalizedStringKey, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        self.init(selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior, matching: filter,
                  preferredItemEncoding: preferredItemEncoding) { Text(titleKey) }
    }

    /// A picker for several items, titled with a string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                                   selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                                   preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        self.init(selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior, matching: filter,
                  preferredItemEncoding: preferredItemEncoding) { Text(title) }
    }

    /// A picker for several items of the library, titled with a localized key.
    public init(_ titleKey: LocalizedStringKey, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic, photoLibrary: PHPhotoLibrary) {
        self.init(selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior, matching: filter,
                  preferredItemEncoding: preferredItemEncoding) { Text(titleKey) }
    }
}

// MARK: - UIKit's picker

/// What a UIKit photo picker offers and how many items it takes.
public struct PHPickerConfiguration: Hashable, Sendable {
    /// Which encoding of an asset the item providers load.
    public enum AssetRepresentationMode: Int, Sendable { case automatic = 0, current = 1, compatible = 2 }
    /// How a picker that takes several items adds to the selection.
    public enum Selection: Int, Sendable { case `default` = 0, ordered = 1, continuous = 2, continuousAndOrdered = 3 }
    /// How the picker shows.
    public enum Mode: Int, Sendable { case `default` = 0, compact = 1 }

    public var preferredAssetRepresentationMode: AssetRepresentationMode = .automatic
    public var selection: Selection = .default
    /// The assets offered; nil for photos and videos.
    public var filter: PHPickerFilter?
    /// How many items the person may choose; 0 for any number.
    public var selectionLimit = 1
    public var preselectedAssetIdentifiers: [String] = []
    public var mode: Mode = .default
    public var disabledCapabilities: PHPickerCapabilities = []

    public init() {}
    /// A configuration whose results carry the assets' identifiers in the library.
    public init(photoLibrary: PHPhotoLibrary) {}
}

/// An item the person chose in a UIKit photo picker.
public struct PHPickerResult: Hashable, @unchecked Sendable {
    /// Loads the item (as `UIImage`, data of a type, a transferable value or a file).
    public let itemProvider: NSItemProvider
    /// The asset's local identifier in the photo library.
    public let assetIdentifier: String?

    package init(itemProvider: NSItemProvider, assetIdentifier: String?) {
        self.itemProvider = itemProvider
        self.assetIdentifier = assetIdentifier
    }

    public static func == (lhs: PHPickerResult, rhs: PHPickerResult) -> Bool {
        lhs.itemProvider === rhs.itemProvider && lhs.assetIdentifier == rhs.assetIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(itemProvider))
        hasher.combine(assetIdentifier)
    }
}

/// Told what the person chose in a UIKit photo picker.
@preconcurrency @MainActor
public protocol PHPickerViewControllerDelegate: AnyObject {
    /// The chosen items, none when the person cancelled. The delegate dismisses the picker.
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult])
}

/// UIKit's photo picker: presented, it opens the host's file panel for the configuration's
/// photos or videos, then hands the delegate an item provider for each file chosen.
open class PHPickerViewController: UIViewController {
    public let configuration: PHPickerConfiguration
    open weak var delegate: (any PHPickerViewControllerDelegate)?
    private var opened = false

    public init(configuration: PHPickerConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !opened else { return }
        opened = true
        guard let open = UIKitScene.shared.fileOpenHandler ?? _appRemount?.runtime.fileOpenHandler else {
            delegate?.picker(self, didFinishPicking: [])
            return
        }
        let limit = max(configuration.selectionLimit, 0)
        open(PHPickerFilter._request(configuration.filter, allowsMultiple: limit != 1)) { [weak self] files in
            guard let self else { return }
            let chosen = limit > 0 ? Array(files.prefix(limit)) : files
            self.delegate?.picker(self, didFinishPicking: chosen.map { PHPickerViewController.result(for: $0) })
        }
    }

    /// The result for a chosen file: a provider of its bytes under its content type.
    @MainActor
    package static func result(for file: HostFile) -> PHPickerResult {
        let (asset, type) = _register(file)
        let item = ExternalDragItem(type: type.identifier, data: file.data, fileName: file.name)
        let provider = _TransferItem(external: [item]).itemProviders(for: [.item]).first ?? NSItemProvider()
        return PHPickerResult(itemProvider: provider, assetIdentifier: asset.localIdentifier)
    }
}

#if !canImport(Darwin)
extension NSItemProvider {
    /// Whether the provider has an image to load as `UIImage`.
    public func canLoadObject(ofClass aClass: UIImage.Type) -> Bool {
        registeredContentTypes.contains { $0.conforms(to: .image) }
    }

    /// Loads the provider's image as a `UIImage` (nil, with an error, when it has none or its
    /// bytes are not an image); the handler runs before the call returns.
    @discardableResult
    public func loadObject(ofClass aClass: UIImage.Type, completionHandler: @escaping @Sendable (Any?, (any Error)?) -> Void) -> Progress {
        loadDataRepresentation(for: .image) { data, error in
            let image = data.flatMap { UIImage(data: $0) }
            completionHandler(image, image == nil ? (error ?? _ItemProviderError(description: "The item is not an image.")) : nil)
        }
    }
}
#endif
