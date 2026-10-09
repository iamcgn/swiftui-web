// UIPasteboard (uk-pasteboard, Docs/elements/DragDrop.md): the general pasteboard over the
// scene's store, whose strings go to the host's clipboard writer (the browser's clipboard, which
// `navigator.clipboard.writeText` takes; reading it back is asynchronous and permission-gated
// there, so the strings read here are the app's own, and the SwiftUI runtime's when a UIKit
// tree is hosted in one), and named pasteboards the app creates.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// Items an app copies and pastes: dictionaries of type identifier to value, as UIKit's.
@MainActor
open class UIPasteboard {
    public struct Name: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let general = Name("com.apple.UIKit.pboard.general")
    }

    public struct OptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let expirationDate = OptionsKey(rawValue: "UIPasteboardOptionExpirationDate")
        public static let localOnly = OptionsKey(rawValue: "UIPasteboardOptionLocalOnly")
    }

    /// The type identifiers the convenience properties use (`UTType`'s, spelled out).
    public static let typeListString = ["public.utf8-plain-text", "public.plain-text", "public.text"]
    public static let typeListURL = ["public.url", "public.file-url"]
    public static let typeListImage = ["public.png", "public.jpeg", "public.image"]
    public static let typeListColor = ["com.apple.uikit.color"]

    /// The general pasteboard, shared with the host's clipboard and a hosting SwiftUI runtime.
    public static let general = UIPasteboard(name: .general, isGeneral: true)
    private static var named: [Name: UIPasteboard] = [:]

    public let name: Name
    public let isPersistent: Bool
    private let isGeneral: Bool
    public private(set) var changeCount = 0
    private var store: [[String: Any]] = []

    private init(name: Name, isGeneral: Bool) {
        self.name = name
        self.isGeneral = isGeneral
        isPersistent = isGeneral
    }

    /// A named pasteboard, made when `create` says so.
    public convenience init?(name: Name, create: Bool) {
        if name == .general { return nil }
        if let existing = Self.named[name] {
            self.init(name: name, isGeneral: false)
            store = existing.store
            changeCount = existing.changeCount
            Self.named[name] = self
            return
        }
        guard create else { return nil }
        self.init(name: name, isGeneral: false)
        Self.named[name] = self
    }

    /// A pasteboard with a unique name.
    public static func withUniqueName() -> UIPasteboard {
        let board = UIPasteboard(name: Name("com.apple.UIKit.pboard.unique.\(named.count + 1)"), isGeneral: false)
        named[board.name] = board
        return board
    }

    public static func remove(withName name: Name) { named[name] = nil }

    // MARK: Items

    public var items: [[String: Any]] {
        get { store }
        set { setItems(newValue) }
    }

    public var numberOfItems: Int { store.count }

    public func setItems(_ items: [[String: Any]], options: [OptionsKey: Any] = [:]) {
        store = items
        didChange()
    }

    public func addItems(_ items: [[String: Any]]) {
        store += items
        didChange()
    }

    public func pasteboardTypes() -> [String] { store.first.map { Array($0.keys) } ?? [] }

    public func pasteboardTypes(forItemSet itemSet: IndexSet?) -> [[String]] {
        store.enumerated().filter { itemSet?.contains($0.offset) ?? true }.map { Array($0.element.keys) }
    }

    public func contains(pasteboardTypes types: [String]) -> Bool {
        store.first.map { item in types.contains { item[$0] != nil } } ?? false
    }

    public func contains(pasteboardTypes types: [String], inItemSet itemSet: IndexSet?) -> Bool {
        store.enumerated().contains { entry in (itemSet?.contains(entry.offset) ?? true) && types.contains { type in entry.element[type] != nil } }
    }

    public func itemSet(withPasteboardTypes types: [String]) -> IndexSet? {
        var set = IndexSet()
        for (index, item) in store.enumerated() where types.contains(where: { item[$0] != nil }) { set.insert(index) }
        return set.isEmpty ? nil : set
    }

    public func value(forPasteboardType type: String) -> Any? { store.first?[type] }

    public func setValue(_ value: Any, forPasteboardType type: String) {
        if store.isEmpty { store = [[type: value]] } else { store[0][type] = value }
        didChange()
    }

    public func data(forPasteboardType type: String) -> Data? {
        if let data = store.first?[type] as? Data { return data }
        if let string = store.first?[type] as? String { return Data(string.utf8) }
        return nil
    }

    public func data(forPasteboardType type: String, inItemSet itemSet: IndexSet?) -> [Data]? {
        let found = store.enumerated().filter { itemSet?.contains($0.offset) ?? true }.compactMap { $0.element[type] as? Data }
        return found.isEmpty ? nil : found
    }

    public func setData(_ data: Data, forPasteboardType type: String) { setValue(data, forPasteboardType: type) }

    public func values(forPasteboardType type: String, inItemSet itemSet: IndexSet?) -> [Any]? {
        let found = store.enumerated().filter { itemSet?.contains($0.offset) ?? true }.compactMap { $0.element[type] }
        return found.isEmpty ? nil : found
    }

    // MARK: Convenience values

    private func first<T>(_ types: [String], as: T.Type) -> T? {
        for item in store { for type in types { if let value = item[type] as? T { return value } } }
        return nil
    }

    private func all<T>(_ types: [String], as: T.Type) -> [T]? {
        let found = store.compactMap { item in types.lazy.compactMap { item[$0] as? T }.first }
        return found.isEmpty ? nil : found
    }

    /// The first string; on the general pasteboard the hosting runtime's text when it copied
    /// more recently than this store was written (a SwiftUI `copyable` above a hosted UIKit tree).
    public var string: String? {
        get {
            if isGeneral, let source = UIKitScene.shared.pasteboardSource?(), source.generation > sourceGeneration { return source.text }
            return first(Self.typeListString, as: String.self)
        }
        set { replace(newValue.map { [[Self.typeListString[0]: $0]] } ?? []) }
    }
    /// The hosting runtime's pasteboard generation when this store was last written.
    private var sourceGeneration = 0

    public var strings: [String]? {
        get { all(Self.typeListString, as: String.self) ?? string.map { [$0] } }
        set { replace((newValue ?? []).map { [Self.typeListString[0]: $0] }) }
    }

    public var url: URL? {
        get { first(Self.typeListURL, as: URL.self) }
        set { replace(newValue.map { [[Self.typeListURL[0]: $0]] } ?? []) }
    }

    public var urls: [URL]? {
        get { all(Self.typeListURL, as: URL.self) }
        set { replace((newValue ?? []).map { [Self.typeListURL[0]: $0] }) }
    }

    public var image: UIImage? {
        get { first(Self.typeListImage, as: UIImage.self) }
        set { replace(newValue.map { [[Self.typeListImage[0]: $0]] } ?? []) }
    }

    public var images: [UIImage]? {
        get { all(Self.typeListImage, as: UIImage.self) }
        set { replace((newValue ?? []).map { [Self.typeListImage[0]: $0] }) }
    }

    public var color: UIColor? {
        get { first(Self.typeListColor, as: UIColor.self) }
        set { replace(newValue.map { [[Self.typeListColor[0]: $0]] } ?? []) }
    }

    public var colors: [UIColor]? {
        get { all(Self.typeListColor, as: UIColor.self) }
        set { replace((newValue ?? []).map { [Self.typeListColor[0]: $0] }) }
    }

    public var hasStrings: Bool { string != nil }
    public var hasURLs: Bool { url != nil }
    public var hasImages: Bool { image != nil }
    public var hasColors: Bool { color != nil }

    // MARK: Item providers

    #if os(WASI)
    /// The items as providers (each value registered under its type); the stand-in delivers
    /// items at once, so providers set here land synchronously.
    public var itemProviders: [NSItemProvider] {
        get {
            store.map { item in
                let provider = NSItemProvider()
                for (type, value) in item { provider.registerItem(value, typeIdentifier: type) }
                return provider
            }
        }
        set { setItemProviders(newValue, localOnly: false, expirationDate: nil) }
    }

    public func setItemProviders(_ providers: [NSItemProvider], localOnly: Bool, expirationDate: Date?) {
        var items: [[String: Any]] = []
        for provider in providers {
            var item: [String: Any] = [:]
            for type in provider.registeredTypeIdentifiers {
                provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in if let value { item[type] = value } }
            }
            if !item.isEmpty { items.append(item) }
        }
        replace(items)
    }
    #else
    /// The items' strings as providers; Foundation's providers load asynchronously, so
    /// providers set here land once their strings arrive.
    public var itemProviders: [NSItemProvider] {
        get { (strings ?? []).map { NSItemProvider(object: $0 as NSString) } }
        set { setItemProviders(newValue, localOnly: false, expirationDate: nil) }
    }

    public func setItemProviders(_ providers: [NSItemProvider], localOnly: Bool, expirationDate: Date?) {
        replace([])
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                Task { @MainActor in self.addItems([[Self.typeListString[0]: text]]) }
            }
        }
    }
    #endif

    public func setObjects(_ objects: [Any], localOnly: Bool = false, expirationDate: Date? = nil) {
        replace(objects.map { object in
            switch object {
            case let string as String: return [Self.typeListString[0]: string]
            case let url as URL: return [Self.typeListURL[0]: url]
            case let image as UIImage: return [Self.typeListImage[0]: image]
            case let color as UIColor: return [Self.typeListColor[0]: color]
            default: return ["public.data": object]
            }
        })
    }

    // MARK: Changes

    private func replace(_ items: [[String: Any]]) {
        store = items
        didChange()
    }

    private func didChange() {
        changeCount += 1
        guard isGeneral else { return }
        // The general pasteboard's text reaches the host's clipboard and the hosting runtime.
        let text = first(Self.typeListString, as: String.self)
        let scene = UIKitScene.shared
        if let text { scene.clipboardWriter?(text) }
        scene.pasteboardSink?(text)
        sourceGeneration = scene.pasteboardSource?().generation ?? 0
    }
}

