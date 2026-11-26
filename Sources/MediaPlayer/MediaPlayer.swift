// MediaPlayer on the web (OldOS's iPod app): the media library's items, collections, playlists,
// queries and predicates, the music player controllers, the volume view, and the Now Playing
// and remote command centres. A page has no music library, so the library is empty: queries
// answer no items or collections, authorization is denied, and the system player has nothing to
// play. An app's own items and collections (`MPMediaItemCollection(items:)`) keep what they are
// given, a player keeps the queue it is set to and its modes, and play leaves it stopped, as an
// item here has no asset to play. Remote commands keep their handlers and the Now Playing
// centre its information; nothing outside the page sends a command yet.
#if os(WASI)
@_exported import WebFoundation
#else
import Foundation
#endif
import UIKit

public typealias MPMediaEntityPersistentID = UInt64

// MARK: - Property keys

public let MPMediaEntityPropertyPersistentID = "persistentID"
public let MPMediaItemPropertyPersistentID = "persistentID"
public let MPMediaItemPropertyMediaType = "mediaType"
public let MPMediaItemPropertyTitle = "title"
public let MPMediaItemPropertyAlbumTitle = "albumTitle"
public let MPMediaItemPropertyAlbumPersistentID = "albumPID"
public let MPMediaItemPropertyArtist = "artist"
public let MPMediaItemPropertyArtistPersistentID = "artistPID"
public let MPMediaItemPropertyAlbumArtist = "albumArtist"
public let MPMediaItemPropertyAlbumArtistPersistentID = "albumArtistPID"
public let MPMediaItemPropertyGenre = "genre"
public let MPMediaItemPropertyGenrePersistentID = "genrePID"
public let MPMediaItemPropertyComposer = "composer"
public let MPMediaItemPropertyComposerPersistentID = "composerPID"
public let MPMediaItemPropertyPlaybackDuration = "playbackDuration"
public let MPMediaItemPropertyAlbumTrackNumber = "albumTrackNumber"
public let MPMediaItemPropertyAlbumTrackCount = "albumTrackCount"
public let MPMediaItemPropertyDiscNumber = "discNumber"
public let MPMediaItemPropertyDiscCount = "discCount"
public let MPMediaItemPropertyArtwork = "artwork"
public let MPMediaItemPropertyIsExplicit = "isExplicit"
public let MPMediaItemPropertyLyrics = "lyrics"
public let MPMediaItemPropertyIsCompilation = "isCompilation"
public let MPMediaItemPropertyReleaseDate = "releaseDate"
public let MPMediaItemPropertyBeatsPerMinute = "beatsPerMinute"
public let MPMediaItemPropertyComments = "comments"
public let MPMediaItemPropertyAssetURL = "assetURL"
public let MPMediaItemPropertyIsCloudItem = "isCloudItem"
public let MPMediaItemPropertyHasProtectedAsset = "protectedAsset"
public let MPMediaItemPropertyPodcastTitle = "podcastTitle"
public let MPMediaItemPropertyPodcastPersistentID = "podcastPID"
public let MPMediaItemPropertyPlayCount = "playCount"
public let MPMediaItemPropertySkipCount = "skipCount"
public let MPMediaItemPropertyRating = "rating"
public let MPMediaItemPropertyLastPlayedDate = "lastPlayedDate"
public let MPMediaItemPropertyUserGrouping = "userGrouping"
public let MPMediaItemPropertyBookmarkTime = "bookmarkTime"
public let MPMediaItemPropertyDateAdded = "dateAdded"
public let MPMediaItemPropertyPlaybackStoreID = "playbackStoreID"
public let MPMediaItemPropertyIsPreorder = "isPreorder"

public let MPMediaPlaylistPropertyPersistentID = "playlistPersistentID"
public let MPMediaPlaylistPropertyName = "name"
public let MPMediaPlaylistPropertyPlaylistAttributes = "playlistAttributes"
public let MPMediaPlaylistPropertySeedItems = "seedItems"
public let MPMediaPlaylistPropertyDescriptionText = "descriptionText"
public let MPMediaPlaylistPropertyAuthorDisplayName = "authorDisplayName"

// MARK: - Entities

/// The kinds of media an item is.
public struct MPMediaType: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let music = MPMediaType(rawValue: 1 << 0)
    public static let podcast = MPMediaType(rawValue: 1 << 1)
    public static let audioBook = MPMediaType(rawValue: 1 << 2)
    public static let audioITunesU = MPMediaType(rawValue: 1 << 3)
    public static let anyAudio = MPMediaType(rawValue: 0x00ff)
    public static let movie = MPMediaType(rawValue: 1 << 8)
    public static let tvShow = MPMediaType(rawValue: 1 << 9)
    public static let videoPodcast = MPMediaType(rawValue: 1 << 10)
    public static let musicVideo = MPMediaType(rawValue: 1 << 11)
    public static let videoITunesU = MPMediaType(rawValue: 1 << 12)
    public static let homeVideo = MPMediaType(rawValue: 1 << 13)
    public static let anyVideo = MPMediaType(rawValue: 0xff00)
    public static let any = MPMediaType(rawValue: ~0)
}

/// An entry in the media library: its values by property key.
open class MPMediaEntity: NSObject, @unchecked Sendable {
    var _values: [String: Any]

    init(values: [String: Any]) { _values = values }

    public override init() { _values = [:] }

    /// Whether a predicate may filter on the property (every key above may).
    open class func canFilter(byProperty property: String) -> Bool { true }

    /// The value for a property key, nil when the entity has none.
    open func value(forProperty property: String) -> Any? { _values[property] }

    /// Calls the block with each of the properties' values.
    open func enumerateValues(forProperties properties: Set<String>,
                              using block: (String, Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for property in properties.sorted() {
            guard let value = _values[property] else { continue }
            block(property, value, &stop)
            if stop.boolValue { return }
        }
    }

    open subscript(key: Any) -> Any? { (key as? String).flatMap { _values[$0] } }

    open var persistentID: MPMediaEntityPersistentID {
        _values[MPMediaEntityPropertyPersistentID] as? MPMediaEntityPersistentID ?? 0
    }
}

/// A song, podcast episode, audiobook or video in the library.
open class MPMediaItem: MPMediaEntity, @unchecked Sendable {
    public override init() { super.init() }

    /// The persistent identifier of the property's value, for the properties that have one.
    open class func persistentIDProperty(forGroupingType groupingType: MPMediaGrouping) -> String {
        switch groupingType {
        case .title: return MPMediaItemPropertyPersistentID
        case .album: return MPMediaItemPropertyAlbumPersistentID
        case .artist: return MPMediaItemPropertyArtistPersistentID
        case .albumArtist: return MPMediaItemPropertyAlbumArtistPersistentID
        case .composer: return MPMediaItemPropertyComposerPersistentID
        case .genre: return MPMediaItemPropertyGenrePersistentID
        case .playlist: return MPMediaPlaylistPropertyPersistentID
        case .podcastTitle: return MPMediaItemPropertyPodcastPersistentID
        }
    }

    /// The property that titles a grouping.
    open class func titleProperty(forGroupingType groupingType: MPMediaGrouping) -> String {
        switch groupingType {
        case .title: return MPMediaItemPropertyTitle
        case .album: return MPMediaItemPropertyAlbumTitle
        case .artist: return MPMediaItemPropertyArtist
        case .albumArtist: return MPMediaItemPropertyAlbumArtist
        case .composer: return MPMediaItemPropertyComposer
        case .genre: return MPMediaItemPropertyGenre
        case .playlist: return MPMediaPlaylistPropertyName
        case .podcastTitle: return MPMediaItemPropertyPodcastTitle
        }
    }

    private func id(_ key: String) -> MPMediaEntityPersistentID { _values[key] as? MPMediaEntityPersistentID ?? 0 }
    private func int(_ key: String) -> Int { _values[key] as? Int ?? 0 }
    private func bool(_ key: String) -> Bool { _values[key] as? Bool ?? false }

    open var mediaType: MPMediaType { _values[MPMediaItemPropertyMediaType] as? MPMediaType ?? .music }
    open var title: String? { _values[MPMediaItemPropertyTitle] as? String }
    open var albumTitle: String? { _values[MPMediaItemPropertyAlbumTitle] as? String }
    open var albumPersistentID: MPMediaEntityPersistentID { id(MPMediaItemPropertyAlbumPersistentID) }
    open var artist: String? { _values[MPMediaItemPropertyArtist] as? String }
    open var artistPersistentID: MPMediaEntityPersistentID { id(MPMediaItemPropertyArtistPersistentID) }
    open var albumArtist: String? { _values[MPMediaItemPropertyAlbumArtist] as? String }
    open var albumArtistPersistentID: MPMediaEntityPersistentID { id(MPMediaItemPropertyAlbumArtistPersistentID) }
    open var genre: String? { _values[MPMediaItemPropertyGenre] as? String }
    open var genrePersistentID: MPMediaEntityPersistentID { id(MPMediaItemPropertyGenrePersistentID) }
    open var composer: String? { _values[MPMediaItemPropertyComposer] as? String }
    open var composerPersistentID: MPMediaEntityPersistentID { id(MPMediaItemPropertyComposerPersistentID) }
    open var playbackDuration: TimeInterval { _values[MPMediaItemPropertyPlaybackDuration] as? TimeInterval ?? 0 }
    open var albumTrackNumber: Int { int(MPMediaItemPropertyAlbumTrackNumber) }
    open var albumTrackCount: Int { int(MPMediaItemPropertyAlbumTrackCount) }
    open var discNumber: Int { int(MPMediaItemPropertyDiscNumber) }
    open var discCount: Int { int(MPMediaItemPropertyDiscCount) }
    open var artwork: MPMediaItemArtwork? { _values[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork }
    open var isExplicitItem: Bool { bool(MPMediaItemPropertyIsExplicit) }
    open var lyrics: String? { _values[MPMediaItemPropertyLyrics] as? String }
    open var isCompilation: Bool { bool(MPMediaItemPropertyIsCompilation) }
    open var releaseDate: Date? { _values[MPMediaItemPropertyReleaseDate] as? Date }
    open var beatsPerMinute: Int { int(MPMediaItemPropertyBeatsPerMinute) }
    open var comments: String? { _values[MPMediaItemPropertyComments] as? String }
    open var assetURL: URL? { _values[MPMediaItemPropertyAssetURL] as? URL }
    open var isCloudItem: Bool { bool(MPMediaItemPropertyIsCloudItem) }
    open var hasProtectedAsset: Bool { bool(MPMediaItemPropertyHasProtectedAsset) }
    open var podcastTitle: String? { _values[MPMediaItemPropertyPodcastTitle] as? String }
    open var podcastPersistentID: MPMediaEntityPersistentID { id(MPMediaItemPropertyPodcastPersistentID) }
    open var playCount: Int { int(MPMediaItemPropertyPlayCount) }
    open var skipCount: Int { int(MPMediaItemPropertySkipCount) }
    open var rating: Int { int(MPMediaItemPropertyRating) }
    open var lastPlayedDate: Date? { _values[MPMediaItemPropertyLastPlayedDate] as? Date }
    open var userGrouping: String? { _values[MPMediaItemPropertyUserGrouping] as? String }
    open var bookmarkTime: TimeInterval { _values[MPMediaItemPropertyBookmarkTime] as? TimeInterval ?? 0 }
    open var dateAdded: Date { _values[MPMediaItemPropertyDateAdded] as? Date ?? Date(timeIntervalSince1970: 0) }
    open var playbackStoreID: String { _values[MPMediaItemPropertyPlaybackStoreID] as? String ?? "" }
    open var isPreorder: Bool { bool(MPMediaItemPropertyIsPreorder) }
}

/// An item's artwork: an image drawn on request at a size.
open class MPMediaItemArtwork: NSObject, @unchecked Sendable {
    private let handler: (CGSize) -> UIImage

    public init(boundsSize: CGSize, requestHandler: @escaping (CGSize) -> UIImage) {
        bounds = CGRect(origin: .zero, size: boundsSize)
        handler = requestHandler
    }

    @available(*, deprecated, message: "Use init(boundsSize:requestHandler:)")
    public convenience init(image: UIImage) {
        self.init(boundsSize: image.size) { _ in image }
    }

    /// The artwork drawn for the size.
    open func image(at size: CGSize) -> UIImage? { handler(size) }
    open private(set) var bounds: CGRect
    open var imageCropRect: CGRect { bounds }
}

/// A set of items: an album, an artist's items, a playlist or an app's own queue.
open class MPMediaItemCollection: MPMediaEntity, @unchecked Sendable {
    public let items: [MPMediaItem]

    public required init(items: [MPMediaItem]) {
        self.items = items
        super.init()
    }

    open class func collection(with items: [MPMediaItem]) -> Self { Self(items: items) }

    open var representativeItem: MPMediaItem? { items.first }
    open var count: Int { items.count }
    open var mediaTypes: MPMediaType {
        items.reduce(into: MPMediaType()) { $0.formUnion($1.mediaType) }
    }

    open override func value(forProperty property: String) -> Any? {
        super.value(forProperty: property) ?? representativeItem?.value(forProperty: property)
    }
}

/// A playlist's kind.
public struct MPMediaPlaylistAttribute: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let onTheGo = MPMediaPlaylistAttribute(rawValue: 1 << 0)
    public static let smart = MPMediaPlaylistAttribute(rawValue: 1 << 1)
    public static let genius = MPMediaPlaylistAttribute(rawValue: 1 << 2)
}

/// A named list of items.
open class MPMediaPlaylist: MPMediaItemCollection, @unchecked Sendable {
    open var name: String? { _values[MPMediaPlaylistPropertyName] as? String }
    open override var persistentID: MPMediaEntityPersistentID {
        _values[MPMediaPlaylistPropertyPersistentID] as? MPMediaEntityPersistentID ?? 0
    }
    open var playlistAttributes: MPMediaPlaylistAttribute {
        _values[MPMediaPlaylistPropertyPlaylistAttributes] as? MPMediaPlaylistAttribute ?? []
    }
    open var seedItems: [MPMediaItem]? { _values[MPMediaPlaylistPropertySeedItems] as? [MPMediaItem] }
    open var descriptionText: String? { _values[MPMediaPlaylistPropertyDescriptionText] as? String }
    open var authorDisplayName: String? { _values[MPMediaPlaylistPropertyAuthorDisplayName] as? String }
    /// Playlists can't be written to: there is no library to add to.
    open func addItem(withProductID productID: String, completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(MPError(.permissionDenied))
    }
    open func add(_ mediaItems: [MPMediaItem], completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(MPError(.permissionDenied))
    }
}

/// An error from the media library or a player.
public struct MPError: Error, Hashable, Sendable {
    public enum Code: Int, Sendable {
        case unknown = 0, permissionDenied, cloudServiceCapabilityMissing, networkConnectionFailed,
             notFound, notSupported, cancelled, requestTimedOut
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public static let errorDomain = "MPErrorDomain"
}

// MARK: - Queries

public enum MPMediaGrouping: Int, Sendable {
    case title = 0, album, artist, albumArtist, composer, genre, playlist, podcastTitle
}

/// A filter on items' properties.
open class MPMediaPredicate: NSObject, @unchecked Sendable {
    func _matches(_ entity: MPMediaEntity) -> Bool { true }
}

public enum MPMediaPredicateComparison: Int, Sendable {
    case equalTo = 0, contains
}

/// Items whose property equals, or contains, a value.
open class MPMediaPropertyPredicate: MPMediaPredicate, @unchecked Sendable {
    public let property: String
    public let value: Any?
    public let comparisonType: MPMediaPredicateComparison

    private init(value: Any?, property: String, comparisonType: MPMediaPredicateComparison) {
        self.value = value
        self.property = property
        self.comparisonType = comparisonType
    }

    public convenience init(value: Any?, forProperty property: String) {
        self.init(value: value, property: property, comparisonType: .equalTo)
    }

    public convenience init(value: Any?, forProperty property: String, comparisonType: MPMediaPredicateComparison) {
        self.init(value: value, property: property, comparisonType: comparisonType)
    }

    override func _matches(_ entity: MPMediaEntity) -> Bool {
        let actual = entity.value(forProperty: property)
        switch comparisonType {
        case .contains:
            guard let needle = value as? String, let hay = actual as? String else { return false }
            return hay.lowercased().contains(needle.lowercased())
        case .equalTo:
            return String(describing: actual ?? "nil" as Any) == String(describing: value ?? "nil" as Any)
        }
    }
}

/// The items or collections of a section of a query's results.
open class MPMediaQuerySection: NSObject, @unchecked Sendable {
    public let title: String
    public let range: NSRange
    init(title: String, range: NSRange) {
        self.title = title
        self.range = range
    }
}

/// A query of the library: its items, grouped into collections. The library here is empty.
open class MPMediaQuery: NSObject, @unchecked Sendable {
    open var filterPredicates: Set<MPMediaPredicate>?
    open var groupingType: MPMediaGrouping = .title

    public override init() { super.init() }

    public init(filterPredicates: Set<MPMediaPredicate>?) {
        self.filterPredicates = filterPredicates
        super.init()
    }

    private convenience init(grouping: MPMediaGrouping, type: MPMediaType? = nil) {
        self.init(filterPredicates: nil)
        groupingType = grouping
        if let type {
            addFilterPredicate(MPMediaPropertyPredicate(value: type, forProperty: MPMediaItemPropertyMediaType))
        }
    }

    open func addFilterPredicate(_ predicate: MPMediaPredicate) {
        filterPredicates = (filterPredicates ?? []).union([predicate])
    }

    open func removeFilterPredicate(_ predicate: MPMediaPredicate) {
        filterPredicates?.remove(predicate)
    }

    /// The library's items that every predicate matches: none, as a page has no library.
    open var items: [MPMediaItem]? {
        MPMediaLibrary._items.filter { item in (filterPredicates ?? []).allSatisfy { $0._matches(item) } }
    }

    /// The matching items grouped by the grouping type.
    open var collections: [MPMediaItemCollection]? {
        guard let items else { return nil }
        let key = MPMediaItem.persistentIDProperty(forGroupingType: groupingType)
        var order: [String] = []
        var groups: [String: [MPMediaItem]] = [:]
        for item in items {
            let id = String(describing: item.value(forProperty: key) ?? 0 as MPMediaEntityPersistentID)
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(item)
        }
        return order.map { MPMediaItemCollection(items: groups[$0] ?? []) }
    }

    open var itemSections: [MPMediaQuerySection]? { (items ?? []).isEmpty ? [] : nil }
    open var collectionSections: [MPMediaQuerySection]? { (collections ?? []).isEmpty ? [] : nil }

    open class func albums() -> MPMediaQuery { MPMediaQuery(grouping: .album) }
    open class func artists() -> MPMediaQuery { MPMediaQuery(grouping: .artist) }
    open class func songs() -> MPMediaQuery { MPMediaQuery(grouping: .title, type: .music) }
    open class func playlists() -> MPMediaQuery { MPMediaQuery(grouping: .playlist) }
    open class func podcasts() -> MPMediaQuery { MPMediaQuery(grouping: .podcastTitle, type: .podcast) }
    open class func audiobooks() -> MPMediaQuery { MPMediaQuery(grouping: .title, type: .audioBook) }
    open class func compilations() -> MPMediaQuery { MPMediaQuery(grouping: .album) }
    open class func composers() -> MPMediaQuery { MPMediaQuery(grouping: .composer) }
    open class func genres() -> MPMediaQuery { MPMediaQuery(grouping: .genre) }
}

// MARK: - Library

public enum MPMediaLibraryAuthorizationStatus: Int, Sendable {
    case notDetermined = 0, denied, restricted, authorized
}

/// The device's media library: a page has none, so access is denied and it holds nothing.
open class MPMediaLibrary: NSObject, @unchecked Sendable {
    private static let shared = MPMediaLibrary()
    static var _items: [MPMediaItem] { [] }

    open class func `default`() -> MPMediaLibrary { shared }
    open class func authorizationStatus() -> MPMediaLibraryAuthorizationStatus { .denied }
    open class func requestAuthorization(_ handler: @escaping (MPMediaLibraryAuthorizationStatus) -> Void) {
        handler(.denied)
    }
    open class func requestAuthorization() async -> MPMediaLibraryAuthorizationStatus { .denied }

    open var lastModifiedDate: Date { Date(timeIntervalSince1970: 0) }
    open func beginGeneratingLibraryChangeNotifications() {}
    open func endGeneratingLibraryChangeNotifications() {}
    open func addItem(withProductID productID: String, completionHandler: (([MPMediaEntity], Error?) -> Void)? = nil) {
        completionHandler?([], MPError(.permissionDenied))
    }
    open func getPlaylist(with uuid: UUID, creationMetadata: MPMediaPlaylistCreationMetadata?,
                          completionHandler: @escaping (MPMediaPlaylist?, Error?) -> Void) {
        completionHandler(nil, MPError(.permissionDenied))
    }
}

/// The name and description a playlist is made with.
open class MPMediaPlaylistCreationMetadata: NSObject, @unchecked Sendable {
    public let name: String
    open var authorDisplayName: String?
    open var descriptionText: String = ""
    public init(name: String) { self.name = name }
}

extension Notification.Name {
    public static let MPMediaLibraryDidChange = Notification.Name("MPMediaLibraryDidChangeNotification")
    public static let MPMusicPlayerControllerPlaybackStateDidChange = Notification.Name("MPMusicPlayerControllerPlaybackStateDidChangeNotification")
    public static let MPMusicPlayerControllerNowPlayingItemDidChange = Notification.Name("MPMusicPlayerControllerNowPlayingItemDidChangeNotification")
    public static let MPMusicPlayerControllerVolumeDidChange = Notification.Name("MPMusicPlayerControllerVolumeDidChangeNotification")
    public static let MPMusicPlayerControllerQueueDidChange = Notification.Name("MPMusicPlayerControllerQueueDidChangeNotification")
}

// MARK: - Players

public enum MPMusicPlaybackState: Int, Sendable {
    case stopped = 0, playing, paused, interrupted, seekingForward, seekingBackward
}

public enum MPMusicRepeatMode: Int, Sendable {
    case `default` = 0, none, one, all
}

public enum MPMusicShuffleMode: Int, Sendable {
    case `default` = 0, off, songs, albums
}

/// Playing, pausing and seeking.
public protocol MPMediaPlayback {
    func prepareToPlay()
    var isPreparedToPlay: Bool { get }
    func play()
    func pause()
    func stop()
    var currentPlaybackTime: TimeInterval { get set }
    var currentPlaybackRate: Float { get set }
    func beginSeekingForward()
    func beginSeekingBackward()
    func endSeeking()
}

/// A queue for a player: items, a query or store identifiers.
open class MPMusicPlayerQueueDescriptor: NSObject, @unchecked Sendable {
    var _items: [MPMediaItem] { [] }
}

open class MPMusicPlayerMediaItemQueueDescriptor: MPMusicPlayerQueueDescriptor, @unchecked Sendable {
    public let query: MPMediaQuery
    open var itemCollection: MPMediaItemCollection
    open var startItem: MPMediaItem?
    public init(query: MPMediaQuery) {
        self.query = query
        itemCollection = MPMediaItemCollection(items: query.items ?? [])
    }
    public init(itemCollection: MPMediaItemCollection) {
        self.query = MPMediaQuery()
        self.itemCollection = itemCollection
    }
    override var _items: [MPMediaItem] { itemCollection.items }
}

open class MPMusicPlayerStoreQueueDescriptor: MPMusicPlayerQueueDescriptor, @unchecked Sendable {
    open var storeIDs: [String]?
    open var startItemID: String?
    public init(storeIDs: [String]) { self.storeIDs = storeIDs }
}

/// Plays items from the library. Here an item has no asset to play, so a player keeps its
/// queue, its now-playing item and its modes, and stays stopped when told to play.
open class MPMusicPlayerController: NSObject, MPMediaPlayback, @unchecked Sendable {
    private static let system = MPMusicPlayerController()
    private static let application = MPMusicPlayerController()
    private static let queue = MPMusicPlayerApplicationController()

    open class var systemMusicPlayer: MPMusicPlayerController { system }
    open class var applicationMusicPlayer: MPMusicPlayerController { application }
    open class var applicationQueuePlayer: MPMusicPlayerApplicationController { queue }
    @available(*, deprecated, renamed: "systemMusicPlayer")
    open class var iPodMusicPlayer: MPMusicPlayerController { system }

    var _queue: [MPMediaItem] = []
    private var notifying = false

    public override init() { super.init() }

    open private(set) var playbackState: MPMusicPlaybackState = .stopped {
        didSet { if oldValue != playbackState { post(.MPMusicPlayerControllerPlaybackStateDidChange) } }
    }
    open var repeatMode: MPMusicRepeatMode = .default
    open var shuffleMode: MPMusicShuffleMode = .default
    open var nowPlayingItem: MPMediaItem? {
        didSet { if oldValue !== nowPlayingItem { post(.MPMusicPlayerControllerNowPlayingItemDidChange) } }
    }
    open var indexOfNowPlayingItem: Int {
        guard let item = nowPlayingItem else { return NSNotFound }
        return _queue.firstIndex { $0 === item } ?? NSNotFound
    }

    open func setQueue(with query: MPMediaQuery) { _setQueue(query.items ?? []) }
    open func setQueue(with itemCollection: MPMediaItemCollection) { _setQueue(itemCollection.items) }
    open func setQueue(with storeIDs: [String]) { _setQueue([]) }
    open func setQueue(with descriptor: MPMusicPlayerQueueDescriptor) {
        _setQueue(descriptor._items)
        if let start = (descriptor as? MPMusicPlayerMediaItemQueueDescriptor)?.startItem { nowPlayingItem = start }
    }

    func _setQueue(_ items: [MPMediaItem]) {
        _queue = items
        nowPlayingItem = items.first
        post(.MPMusicPlayerControllerQueueDidChange)
    }

    open func prepend(_ descriptor: MPMusicPlayerQueueDescriptor) { _queue.insert(contentsOf: descriptor._items, at: 0) }
    open func append(_ descriptor: MPMusicPlayerQueueDescriptor) { _queue.append(contentsOf: descriptor._items) }

    open func skipToNextItem() { skip(by: 1) }
    open func skipToPreviousItem() { skip(by: -1) }
    open func skipToBeginning() { currentPlaybackTime = 0 }

    private func skip(by step: Int) {
        let index = indexOfNowPlayingItem
        guard index != NSNotFound else { return }
        let next = index + step
        nowPlayingItem = _queue.indices.contains(next) ? _queue[next] : nil
        currentPlaybackTime = 0
    }

    open func beginGeneratingPlaybackNotifications() { notifying = true }
    open func endGeneratingPlaybackNotifications() { notifying = false }

    private func post(_ name: Notification.Name) {
        guard notifying else { return }
        NotificationCenter.default.post(name: name, object: self)
    }

    // MPMediaPlayback: nothing plays, so the player stays stopped.
    open func prepareToPlay() {}
    open func prepareToPlay(completionHandler: @escaping (Error?) -> Void) { completionHandler(MPError(.notSupported)) }
    open var isPreparedToPlay: Bool { false }
    open func play() {}
    open func pause() { if playbackState == .playing { playbackState = .paused } }
    open func stop() {
        playbackState = .stopped
        currentPlaybackTime = 0
    }
    open var currentPlaybackTime: TimeInterval = 0
    open var currentPlaybackRate: Float = 0
    open func beginSeekingForward() {}
    open func beginSeekingBackward() {}
    open func endSeeking() {}

    @available(*, deprecated, message: "Use MPVolumeView")
    open var volume: Float = 1
}

/// The application queue player, whose queue an app can edit.
open class MPMusicPlayerApplicationController: MPMusicPlayerController, @unchecked Sendable {
    open func perform(queueTransaction: @escaping (MPMusicPlayerControllerMutableQueue) -> Void,
                      completionHandler: @escaping (MPMusicPlayerControllerQueue, Error?) -> Void) {
        let mutable = MPMusicPlayerControllerMutableQueue(items: _queue)
        queueTransaction(mutable)
        _queue = mutable.items
        completionHandler(MPMusicPlayerControllerQueue(items: _queue), nil)
    }
}

/// A player's queue as it stands.
open class MPMusicPlayerControllerQueue: NSObject, @unchecked Sendable {
    open fileprivate(set) var items: [MPMediaItem]
    init(items: [MPMediaItem]) { self.items = items }
}

/// A queue an app edits inside a transaction.
open class MPMusicPlayerControllerMutableQueue: MPMusicPlayerControllerQueue, @unchecked Sendable {
    open func insert(_ queueDescriptor: MPMusicPlayerQueueDescriptor, after item: MPMediaItem?) {
        let at = item.flatMap { item in items.firstIndex { $0 === item } }.map { $0 + 1 } ?? 0
        items.insert(contentsOf: queueDescriptor._items, at: at)
    }
    open func remove(_ item: MPMediaItem) { items.removeAll { $0 === item } }
}

// MARK: - Volume view

/// The system volume slider and route button. The page's volume is the browser's, so the
/// slider is the view's own: an app reads and sets its value.
open class MPVolumeView: UIView {
    public required init?(coder: NSCoder) { return nil }

    private let slider = UISlider()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        slider.value = 1
        addSubview(slider)
    }

    open var showsVolumeSlider = true { didSet { slider.isHidden = !showsVolumeSlider } }
    @available(*, deprecated, message: "Use AVRoutePickerView")
    open var showsRouteButton = true
    open var areWirelessRoutesAvailable: Bool { false }
    open var isWirelessRouteActive: Bool { false }

    private var thumbImages: [UInt: UIImage] = [:]
    private var minimumImages: [UInt: UIImage] = [:]
    private var maximumImages: [UInt: UIImage] = [:]

    open func setVolumeThumbImage(_ image: UIImage?, for state: UIControl.State) { thumbImages[state.rawValue] = image }
    open func volumeThumbImage(for state: UIControl.State) -> UIImage? { thumbImages[state.rawValue] }
    open func setMinimumVolumeSliderImage(_ image: UIImage?, for state: UIControl.State) { minimumImages[state.rawValue] = image }
    open func minimumVolumeSliderImage(for state: UIControl.State) -> UIImage? { minimumImages[state.rawValue] }
    open func setMaximumVolumeSliderImage(_ image: UIImage?, for state: UIControl.State) { maximumImages[state.rawValue] = image }
    open func maximumVolumeSliderImage(for state: UIControl.State) -> UIImage? { maximumImages[state.rawValue] }

    open override func layoutSubviews() {
        super.layoutSubviews()
        slider.frame = bounds
    }
}

// MARK: - Now Playing and remote commands

public let MPNowPlayingInfoPropertyElapsedPlaybackTime = "MPNowPlayingInfoPropertyElapsedPlaybackTime"
public let MPNowPlayingInfoPropertyPlaybackRate = "MPNowPlayingInfoPropertyPlaybackRate"
public let MPNowPlayingInfoPropertyDefaultPlaybackRate = "MPNowPlayingInfoPropertyDefaultPlaybackRate"
public let MPNowPlayingInfoPropertyPlaybackQueueIndex = "MPNowPlayingInfoPropertyPlaybackQueueIndex"
public let MPNowPlayingInfoPropertyPlaybackQueueCount = "MPNowPlayingInfoPropertyPlaybackQueueCount"
public let MPNowPlayingInfoPropertyMediaType = "MPNowPlayingInfoPropertyMediaType"
public let MPNowPlayingInfoPropertyIsLiveStream = "MPNowPlayingInfoPropertyIsLiveStream"
public let MPNowPlayingInfoPropertyPlaybackProgress = "MPNowPlayingInfoPropertyPlaybackProgress"
public let MPNowPlayingInfoPropertyAssetURL = "MPNowPlayingInfoPropertyAssetURL"
public let MPNowPlayingInfoPropertyExternalContentIdentifier = "MPNowPlayingInfoPropertyExternalContentIdentifier"

public enum MPNowPlayingInfoMediaType: UInt, Sendable {
    case none = 0, audio, video
}

public enum MPNowPlayingPlaybackState: UInt, Sendable {
    case unknown = 0, playing, paused, stopped, interrupted
}

/// What the app says is playing, for the system's Now Playing controls.
open class MPNowPlayingInfoCenter: NSObject, @unchecked Sendable {
    private static let shared = MPNowPlayingInfoCenter()
    open class func `default`() -> MPNowPlayingInfoCenter { shared }
    open var nowPlayingInfo: [String: Any]?
    open var playbackState: MPNowPlayingPlaybackState = .unknown
}

public enum MPRemoteCommandHandlerStatus: Int, Sendable {
    case success = 0, noSuchContent = 100, noActionableNowPlayingItem = 110, deviceNotFound = 120, commandFailed = 200
}

/// A command's event: the command and when it came.
open class MPRemoteCommandEvent: NSObject, @unchecked Sendable {
    public let command: MPRemoteCommand
    public let timestamp: TimeInterval
    init(command: MPRemoteCommand) {
        self.command = command
        timestamp = Date().timeIntervalSince1970
    }
}

open class MPSkipIntervalCommandEvent: MPRemoteCommandEvent, @unchecked Sendable {
    public let interval: TimeInterval
    init(command: MPRemoteCommand, interval: TimeInterval) {
        self.interval = interval
        super.init(command: command)
    }
}

open class MPChangePlaybackPositionCommandEvent: MPRemoteCommandEvent, @unchecked Sendable {
    public let positionTime: TimeInterval
    init(command: MPRemoteCommand, positionTime: TimeInterval) {
        self.positionTime = positionTime
        super.init(command: command)
    }
}

open class MPChangePlaybackRateCommandEvent: MPRemoteCommandEvent, @unchecked Sendable {
    public let playbackRate: Float
    init(command: MPRemoteCommand, playbackRate: Float) {
        self.playbackRate = playbackRate
        super.init(command: command)
    }
}

public enum MPSeekCommandEventType: UInt, Sendable { case beginSeeking = 0, endSeeking }

open class MPSeekCommandEvent: MPRemoteCommandEvent, @unchecked Sendable {
    public let type: MPSeekCommandEventType
    init(command: MPRemoteCommand, type: MPSeekCommandEventType) {
        self.type = type
        super.init(command: command)
    }
}

/// A command the system's controls send; an app adds handlers to answer it.
open class MPRemoteCommand: NSObject, @unchecked Sendable {
    open var isEnabled = true
    private var handlers: [(token: NSObject, handler: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus)] = []
    private var actions: [(target: AnyObject, action: Selector)] = []

    override init() { super.init() }

    /// Adds a handler; the returned object removes it again.
    @discardableResult
    open func addTarget(handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any {
        let token = NSObject()
        handlers.append((token, handler))
        return token
    }

    open func addTarget(_ target: Any, action: Selector) {
        actions.append((target as AnyObject, action))
    }

    open func removeTarget(_ target: Any?) {
        guard let target = target as AnyObject? else {
            handlers.removeAll()
            actions.removeAll()
            return
        }
        handlers.removeAll { $0.token === target }
        actions.removeAll { $0.target === target }
    }

    open func removeTarget(_ target: Any?, action: Selector?) {
        guard let target = target as AnyObject? else { return removeTarget(nil) }
        actions.removeAll { $0.target === target && (action == nil || $0.action == action) }
    }

    /// Whether any handler or target answers the command.
    public var _hasTargets: Bool { !handlers.isEmpty || !actions.isEmpty }

    /// Sends the event to the command's handlers, as the system's controls would; the first
    /// status that isn't success is the answer.
    @discardableResult
    public func _send(_ event: MPRemoteCommandEvent? = nil) -> MPRemoteCommandHandlerStatus {
        guard isEnabled else { return .commandFailed }
        let event = event ?? MPRemoteCommandEvent(command: self)
        var status = MPRemoteCommandHandlerStatus.success
        for (_, handler) in handlers {
            let answer = handler(event)
            if answer != .success, status == .success { status = answer }
        }
        return status
    }
}

open class MPSkipIntervalCommand: MPRemoteCommand, @unchecked Sendable {
    open var preferredIntervals: [NSNumber] = [15]
    /// Sends a skip by the interval.
    @discardableResult
    public func _send(interval: TimeInterval) -> MPRemoteCommandHandlerStatus {
        _send(MPSkipIntervalCommandEvent(command: self, interval: interval))
    }
}

open class MPChangePlaybackPositionCommand: MPRemoteCommand, @unchecked Sendable {
    @discardableResult
    public func _send(positionTime: TimeInterval) -> MPRemoteCommandHandlerStatus {
        _send(MPChangePlaybackPositionCommandEvent(command: self, positionTime: positionTime))
    }
}

open class MPChangePlaybackRateCommand: MPRemoteCommand, @unchecked Sendable {
    open var supportedPlaybackRates: [NSNumber] = []
}

open class MPFeedbackCommand: MPRemoteCommand, @unchecked Sendable {
    open var isActive = false
    open var localizedTitle = ""
    open var localizedShortTitle = ""
}

open class MPRatingCommand: MPRemoteCommand, @unchecked Sendable {
    open var minimumRating: Float = 0
    open var maximumRating: Float = 0
}

public enum MPRepeatType: Int, Sendable { case off = 0, one, all }
public enum MPShuffleType: Int, Sendable { case off = 0, items, collections }

open class MPChangeRepeatModeCommand: MPRemoteCommand, @unchecked Sendable {
    open var currentRepeatType: MPRepeatType = .off
}

open class MPChangeShuffleModeCommand: MPRemoteCommand, @unchecked Sendable {
    open var currentShuffleType: MPShuffleType = .off
}

/// The commands the system's playback controls send to the app.
open class MPRemoteCommandCenter: NSObject, @unchecked Sendable {
    private static let center = MPRemoteCommandCenter()
    open class func shared() -> MPRemoteCommandCenter { center }

    public let pauseCommand = MPRemoteCommand()
    public let playCommand = MPRemoteCommand()
    public let stopCommand = MPRemoteCommand()
    public let togglePlayPauseCommand = MPRemoteCommand()
    public let enableLanguageOptionCommand = MPRemoteCommand()
    public let disableLanguageOptionCommand = MPRemoteCommand()
    public let changePlaybackRateCommand = MPChangePlaybackRateCommand()
    public let changeRepeatModeCommand = MPChangeRepeatModeCommand()
    public let changeShuffleModeCommand = MPChangeShuffleModeCommand()
    public let nextTrackCommand = MPRemoteCommand()
    public let previousTrackCommand = MPRemoteCommand()
    public let skipForwardCommand = MPSkipIntervalCommand()
    public let skipBackwardCommand = MPSkipIntervalCommand()
    public let seekForwardCommand = MPRemoteCommand()
    public let seekBackwardCommand = MPRemoteCommand()
    public let changePlaybackPositionCommand = MPChangePlaybackPositionCommand()
    public let ratingCommand = MPRatingCommand()
    public let likeCommand = MPFeedbackCommand()
    public let dislikeCommand = MPFeedbackCommand()
    public let bookmarkCommand = MPFeedbackCommand()

    override init() { super.init() }
}
