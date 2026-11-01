// AppIntents (sw-frameworks): the actions an app offers Siri, Shortcuts, Spotlight and its
// widgets. A web page has none of those, so the system never runs an intent here: no shortcut
// is registered, nothing is donated, and a parameter is only ever set by the app's own code.
// What does run is the app's own use of its intents: `Button(intent:)` and
// `Toggle(isOn:intent:)` call `perform()`, and an app can call an intent itself, as on iOS.
// The declarations follow Apple's (Xcode 26.3) so the intents, entities and queries apps
// declare compile unchanged; the resolver machinery behind Apple's parameter initializers is
// left out, since nothing here resolves a value from Siri.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

// MARK: Values an intent can take

/// A type an intent parameter, result or entity property can hold.
public protocol _IntentValue {
    /// The type of one value (the element, for a collection; the wrapped type, for an optional).
    associatedtype ValueType: _IntentValue = Self
    /// The type without its optional (a collection stays a collection).
    associatedtype UnwrappedType: _IntentValue = Self
}

extension Optional: _IntentValue where Wrapped: _IntentValue {
    public typealias ValueType = Wrapped.ValueType
    public typealias UnwrappedType = Wrapped.UnwrappedType
}

extension Array: _IntentValue where Element: _IntentValue {
    public typealias ValueType = Element
    public typealias UnwrappedType = [Element]
}

extension Set: _IntentValue where Element: _IntentValue {
    public typealias ValueType = Element
    public typealias UnwrappedType = Set<Element>
}

extension String: _IntentValue {}
extension Int: _IntentValue {}
extension Double: _IntentValue {}
extension Bool: _IntentValue {}
extension Date: _IntentValue {}
extension URL: _IntentValue {}
extension DateComponents: _IntentValue {}
extension AttributedString: _IntentValue {}
extension Measurement: _IntentValue {}

extension Never: _IntentValue {
    public typealias ValueType = Never
    public typealias UnwrappedType = Never
}

/// A value with an identity that survives across launches: the type's name, here.
public protocol PersistentlyIdentifiable {
    static var persistentIdentifier: String { get }
}

extension PersistentlyIdentifiable {
    public static var persistentIdentifier: String { String(describing: Self.self) }
}

/// A type whose values Shortcuts and Siri can show and pass around.
public protocol AppValue: PersistentlyIdentifiable, TypeDisplayRepresentable, _IntentValue, Sendable {}

/// A parameter or property: its title and whether it may be empty.
public protocol AnyIntentValue: Sendable {
    associatedtype Value: _IntentValue, Sendable
    var isOptional: Bool { get }
    var title: LocalizedStringResource { get }
}

// MARK: Display representations

/// How the system shows a type: its name.
public struct TypeDisplayRepresentation: ExpressibleByStringLiteral, @unchecked Sendable {
    public var name: LocalizedStringResource
    public var numericFormat: LocalizedStringResource?
    public var synonyms: [LocalizedStringResource]

    public init(name: LocalizedStringResource, numericFormat: LocalizedStringResource? = nil) {
        self.init(name: name, numericFormat: numericFormat, synonyms: [])
    }

    public init(name: LocalizedStringResource, numericFormat: LocalizedStringResource? = nil, synonyms: [LocalizedStringResource] = []) {
        self.name = name
        self.numericFormat = numericFormat
        self.synonyms = synonyms
    }

    public init(stringLiteral value: String) { self.init(name: LocalizedStringResource(stringLiteral: value)) }
}

/// How the system shows one value: a title, a subtitle and an image.
public struct DisplayRepresentation: ExpressibleByStringLiteral, Equatable, @unchecked Sendable {
    public var title: LocalizedStringResource
    public var subtitle: LocalizedStringResource?
    public var image: DisplayRepresentation.Image?
    public var synonyms: [LocalizedStringResource]

    public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: DisplayRepresentation.Image? = nil) {
        self.init(title: title, subtitle: subtitle, image: image, synonyms: [])
    }

    public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: DisplayRepresentation.Image? = nil, synonyms: [LocalizedStringResource] = []) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.synonyms = synonyms
    }

    public init(stringLiteral value: String) { self.init(title: LocalizedStringResource(stringLiteral: value)) }

    public static func == (a: DisplayRepresentation, b: DisplayRepresentation) -> Bool {
        a.title == b.title && a.subtitle == b.subtitle && a.image == b.image && a.synonyms == b.synonyms
    }

    /// The image beside a value: a symbol, a named image, a URL or image data.
    public struct Image: Equatable, @unchecked Sendable {
        public enum Source: Equatable, Sendable {
            case systemName(String)
            case named(String)
            case url(URL)
            case data(Data)
        }

        /// Where the image comes from.
        public let source: Source
        public var isTemplate: Bool
        public var displayStyle: DisplayStyle

        /// How the image is framed.
        public enum DisplayStyle: Equatable, Sendable {
            case `default`
            case circular
        }

        public init(systemName: String, isTemplate: Bool = true) {
            source = .systemName(systemName)
            self.isTemplate = isTemplate
            displayStyle = .default
        }

        public init(named name: String, isTemplate: Bool = false, displayStyle: DisplayStyle = .default) {
            source = .named(name)
            self.isTemplate = isTemplate
            self.displayStyle = displayStyle
        }

        public init(url: URL, isTemplate: Bool = false, displayStyle: DisplayStyle = .default) {
            source = .url(url)
            self.isTemplate = isTemplate
            self.displayStyle = displayStyle
        }

        public init(data: Data, isTemplate: Bool = false, displayStyle: DisplayStyle = .default) {
            source = .data(data)
            self.isTemplate = isTemplate
            self.displayStyle = displayStyle
        }
    }
}

/// A type that names itself to the system.
public protocol TypeDisplayRepresentable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { get }
}

/// A value that shows itself to the system.
public protocol InstanceDisplayRepresentable: CustomLocalizedStringResourceConvertible {
    var displayRepresentation: DisplayRepresentation { get }
}

extension InstanceDisplayRepresentable {
    public var localizedStringResource: LocalizedStringResource { displayRepresentation.title }
}

/// An enumeration whose cases each show themselves to the system.
public protocol CaseDisplayRepresentable: CustomLocalizedStringResourceConvertible, CaseIterable, Hashable {
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { get }
}

extension CaseDisplayRepresentable {
    public var localizedStringResource: LocalizedStringResource {
        Self.caseDisplayRepresentations[self]?.title ?? LocalizedStringResource(stringLiteral: String(describing: self))
    }
}

public protocol DisplayRepresentable: InstanceDisplayRepresentable, TypeDisplayRepresentable {}
public protocol StaticDisplayRepresentable: CaseDisplayRepresentable, TypeDisplayRepresentable {}

// MARK: Entities and enumerations

/// A value of the app's own (a document, a person, a place) that intents take and return.
public protocol AppEntity: AppValue, DisplayRepresentable, Identifiable where Self == Self.ValueType, Self.ID: EntityIdentifierConvertible, Self.ID: Sendable {
    associatedtype DefaultQuery: EntityQuery where Self.ValueType == Self.DefaultQuery.Entity
    /// The query the system uses to find entities by identifier.
    static var defaultQuery: Self.DefaultQuery { get }
}

extension AppEntity {
    public typealias Property = EntityProperty
}

/// A type an entity's identifier can be: it converts to and from a string.
public protocol EntityIdentifierConvertible {
    var entityIdentifierString: String { get }
    static func entityIdentifier(for entityIdentifierString: String) -> Self?
}

extension String: EntityIdentifierConvertible {
    public var entityIdentifierString: String { self }
    public static func entityIdentifier(for entityIdentifierString: String) -> String? { entityIdentifierString }
}

extension UUID: EntityIdentifierConvertible {
    public var entityIdentifierString: String { uuidString }
    public static func entityIdentifier(for entityIdentifierString: String) -> UUID? { UUID(uuidString: entityIdentifierString) }
}

extension Int: EntityIdentifierConvertible {
    public var entityIdentifierString: String { String(self) }
    public static func entityIdentifier(for entityIdentifierString: String) -> Int? { Int(entityIdentifierString) }
}

extension Int64: EntityIdentifierConvertible {
    public var entityIdentifierString: String { String(self) }
    public static func entityIdentifier(for entityIdentifierString: String) -> Int64? { Int64(entityIdentifierString) }
}

extension UInt64: EntityIdentifierConvertible {
    public var entityIdentifierString: String { String(self) }
    public static func entityIdentifier(for entityIdentifierString: String) -> UInt64? { UInt64(entityIdentifierString) }
}

/// A fixed set of values an intent can take, each shown by its case representation.
public protocol AppEnum: AppValue, StaticDisplayRepresentable, RawRepresentable where Self.RawValue: LosslessStringConvertible {}

// MARK: Queries and options

/// A collection of values offered to choose from.
public protocol ResultsCollection<Result> {
    associatedtype Result: _IntentValue
    var promptLabel: LocalizedStringResource? { get }
    var usesIndexedCollation: Bool { get }
    var items: [Self.Result.ValueType] { get }
    static var empty: Self { get }
}

extension Array: ResultsCollection where Element: _IntentValue {
    public typealias Result = Element
    public var promptLabel: LocalizedStringResource? { nil }
    public var usesIndexedCollation: Bool { false }
    public var items: [Element.ValueType] { compactMap { $0 as? Element.ValueType } }
    public static var empty: [Element] { [] }
}

/// The options for a parameter, which the app computes.
public protocol DynamicOptionsProvider: _SupportsAppDependencies {
    associatedtype Result: ResultsCollection
    associatedtype DefaultValue: _IntentValue = Self.Result.Result where Self.DefaultValue.ValueType == Self.Result.Result.ValueType
    func results() async throws -> Self.Result
    func defaultResult() async -> Self.DefaultValue?
}

extension DynamicOptionsProvider {
    public typealias ItemCollection = IntentItemCollection
    public typealias ItemSection<R> = IntentItemSection<R> where R == Self.Result.Result
    public typealias Item<R> = IntentItem<R> where R == Self.Result.Result

    public func defaultResult() async -> Self.DefaultValue? { nil }
}

/// A type that can declare dependencies the system supplies (none here).
public protocol _SupportsAppDependencies {}

/// The query that finds an entity type's entities by identifier.
public protocol EntityQuery: DynamicOptionsProvider, PersistentlyIdentifiable, Sendable {
    associatedtype Entity: AppEntity = Self.Result.Result.ValueType where Self.Entity == Self.Result.Result
    associatedtype Result = [Self.Entity]
    init()
    func entities(for identifiers: [Self.Entity.ID]) async throws -> [Self.Entity]
    func suggestedEntities() async throws -> Self.Result
}

extension EntityQuery {
    /// No suggestions, unless the query offers some.
    public func suggestedEntities() async throws -> Self.Result { Self.Result.empty }
    public func results() async throws -> Self.Result { try await suggestedEntities() }
}

/// A query that also finds entities by a search string.
public protocol EntityStringQuery: EntityQuery {
    func entities(matching string: String) async throws -> Self.Result
}

/// A query that can list every entity.
public protocol EnumerableEntityQuery: EntityQuery {
    func allEntities() async throws -> Self.Result
    static var findIntentDescription: IntentDescription? { get }
}

extension EnumerableEntityQuery {
    public static var findIntentDescription: IntentDescription? { nil }
    public func suggestedEntities() async throws -> Self.Result { try await allEntities() }
}

/// One value offered to choose from, with how it shows.
public struct IntentItem<Value: _IntentValue> {
    public var value: Value
    public var description: DisplayRepresentation

    public init(_ value: Value, title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: DisplayRepresentation.Image? = nil) {
        self.value = value
        description = DisplayRepresentation(title: title, subtitle: subtitle, image: image)
    }

    public init(_ value: Value) {
        self.value = value
        if let shown = value as? any InstanceDisplayRepresentable {
            description = shown.displayRepresentation
        } else {
            description = DisplayRepresentation(title: LocalizedStringResource(stringLiteral: String(describing: value)))
        }
    }

    @resultBuilder
    public enum Builder {
        public static func buildExpression(_ expression: Value) -> IntentItem<Value> { IntentItem(expression) }
        public static func buildExpression<ExpressionValue: _IntentValue>(_ expression: IntentItem<ExpressionValue>) -> IntentItem<ExpressionValue> { expression }
        public static func buildBlock(_ items: IntentItem<Value>...) -> [IntentItem<Value>] { items }
        public static func buildBlock(_ items: [IntentItem<Value>]) -> [IntentItem<Value>] { items }
        public static func buildArray(_ components: [[IntentItem<Value>]]) -> [IntentItem<Value>] { components.flatMap { $0 } }
    }
}

extension IntentItem: Sendable where Value: Sendable {}

/// A titled group of values offered to choose from.
public struct IntentItemSection<Result: _IntentValue> {
    public var description: DisplayRepresentation?
    public var items: [IntentItem<Result>]

    public init(items: [IntentItem<Result>]) {
        self.items = items
    }

    public init(title: LocalizedStringResource, items: [IntentItem<Result>]) {
        description = DisplayRepresentation(title: title)
        self.items = items
    }

    public init(_ title: LocalizedStringResource, items: [IntentItem<Result>]) {
        self.init(title: title, items: items)
    }

    public init(_ title: LocalizedStringResource, items: [Result]) {
        self.init(title: title, items: items.map { IntentItem($0) })
    }

    public init(_ title: LocalizedStringResource? = nil, @IntentItem<Result>.Builder itemsBuilder: () -> [IntentItem<Result>]) {
        description = title.map { DisplayRepresentation(title: $0) }
        items = itemsBuilder()
    }

    public init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: DisplayRepresentation.Image? = nil, @IntentItem<Result>.Builder itemsBuilder: () -> [IntentItem<Result>]) {
        description = DisplayRepresentation(title: title, subtitle: subtitle, image: image)
        items = itemsBuilder()
    }

    @resultBuilder
    public enum Builder {
        public static func buildBlock() -> [IntentItemSection<Result>] { [] }
        public static func buildBlock(_ sections: IntentItemSection<Result>...) -> [IntentItemSection<Result>] { sections }
        public static func buildBlock(_ items: IntentItem<Result>...) -> [IntentItemSection<Result>] { [IntentItemSection(items: items)] }
    }
}

extension IntentItemSection: Sendable where Result: Sendable {}

/// Values offered to choose from, in sections.
public struct IntentItemCollection<Result: _IntentValue>: ResultsCollection {
    public var sections: [IntentItemSection<Result>]
    public var promptLabel: LocalizedStringResource?
    public var usesIndexedCollation: Bool

    public init(promptLabel: LocalizedStringResource? = nil, usesIndexedCollation: Bool = false, @IntentItemSection<Result>.Builder sectionsBuilder: () -> [IntentItemSection<Result>]) {
        self.init(promptLabel: promptLabel, usesIndexedCollation: usesIndexedCollation, sections: sectionsBuilder())
    }

    public init(promptLabel: LocalizedStringResource? = nil, usesIndexedCollation: Bool = false, items: [Result]) where Result: DisplayRepresentable {
        self.init(promptLabel: promptLabel, usesIndexedCollation: usesIndexedCollation, sections: [IntentItemSection(items: items.map { IntentItem($0) })])
    }

    public init(promptLabel: LocalizedStringResource? = nil, usesIndexedCollation: Bool = false, sections: [IntentItemSection<Result>]) {
        self.sections = sections
        self.promptLabel = promptLabel
        self.usesIndexedCollation = usesIndexedCollation
    }

    /// Every value, in section order.
    public var items: [Result.ValueType] {
        sections.flatMap { $0.items.compactMap { $0.value as? Result.ValueType } }
    }

    public static var empty: IntentItemCollection<Result> { IntentItemCollection(sections: []) }
}

extension IntentItemCollection: Sendable where Result: Sendable {}

// MARK: Files

/// A file an intent takes or returns.
public struct IntentFile: Sendable, Equatable, Hashable {
    /// Why a file's contents couldn't be read.
    public enum IntentFileError: Error, Equatable, Hashable {
        case failedToLoadData
        case failedToLoadFile
    }

    public let filename: String
    public let fileURL: URL?
    public let type: UTType?
    public var removedOnCompletion = false
    private let contents: Data?

    public init(data: Data, filename: String, type: UTType? = nil) {
        contents = data
        self.filename = filename
        fileURL = nil
        self.type = type
    }

    public init(fileURL: URL, filename: String? = nil, type: UTType? = nil) {
        contents = nil
        self.fileURL = fileURL
        self.filename = filename ?? fileURL.lastPathComponent
        self.type = type
    }

    /// The file's contents: the data it was made with, or the file at its URL (empty when that
    /// can't be read).
    public var data: Data { (try? load()) ?? Data() }

    /// The file's contents as a type.
    public func data(contentType: UTType) async throws -> Data { try load() }

    /// The types the file can be read as.
    public var availableContentTypes: [UTType] { type.map { [$0] } ?? [] }

    private func load() throws -> Data {
        if let contents { return contents }
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { throw IntentFileError.failedToLoadFile }
        return data
    }
}

extension IntentFile: DisplayRepresentable, _IntentValue {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "File" }
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: filename)) }
}
