// Intent parameters, entity properties, dialogs and descriptions. On iOS the system fills an
// intent's parameters before `perform()` runs, asking the user for a missing one. On the web
// only the app sets them: a parameter holds what the app assigned, else its default, and asking
// the user for a value (`requestValue`, `requestDisambiguation`, `requestConfirmation`) throws,
// since there is no one to ask.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// The optional types, so a parameter can answer nil when it holds nothing.
public protocol _OptionalIntentValue {
    static var _none: Self { get }
}

extension Optional: _OptionalIntentValue {
    public static var _none: Optional<Wrapped> { nil }
}

/// What an empty parameter or property answers: its default, nil for an optional, else a trap
/// naming it (as on iOS, where the system never runs an intent with a required value unset).
private func emptyValue<Value>(default defaultValue: Any?, title: LocalizedStringResource, kind: String) -> Value {
    if let defaultValue, let value = defaultValue as? Value { return value }
    if let optional = Value.self as? any _OptionalIntentValue.Type, let none = optional._none as? Value { return none }
    fatalError("\(kind) '\(title.key)' has no value: nothing set it, and it has no default")
}

/// A parameter of an intent: `@Parameter(title: "Account") var account: AccountEntity`.
@propertyWrapper
public final class IntentParameter<Value: _IntentValue & Sendable>: AnyIntentValue, @unchecked Sendable {
    /// The value the parameter holds until something sets it.
    public let defaultValue: Value.UnwrappedType?
    /// The parameter's name, as Shortcuts shows it.
    public let title: LocalizedStringResource
    /// What the parameter is for.
    public let parameterDescription: LocalizedStringResource?
    /// What Siri asks when the parameter has no value.
    public let requestValueDialog: IntentDialog?
    private var value: Value?

    /// The parameter's state: unset until the app or a default gives it a value.
    public enum ValueState {
        case unset
        case set(Value)
    }

    /// How a number parameter is edited in Shortcuts.
    public struct ControlStyle: Hashable, Sendable {
        let name: String
        public static var field: ControlStyle { ControlStyle(name: "field") }
        public static var slider: ControlStyle { ControlStyle(name: "slider") }
        public static var stepper: ControlStyle { ControlStyle(name: "stepper") }
    }

    public typealias IntControlStyle = ControlStyle
    public typealias DoubleControlStyle = ControlStyle
    public typealias InclusiveRange<T> = (lowerBound: T, upperBound: T)

    public init() {
        defaultValue = nil
        title = ""
        parameterDescription = nil
        requestValueDialog = nil
    }

    public init(title: LocalizedStringResource = "", description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil,
                controlStyle: ControlStyle = .stepper, inclusiveRange: InclusiveRange<Value.ValueType>? = nil,
                supportedContentTypes: Set<UTType>? = nil, size: IntentCollectionSize? = nil,
                requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil,
                inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.defaultValue = defaultValue
        self.title = title
        parameterDescription = description
        self.requestValueDialog = requestValueDialog
    }

    /// A parameter whose options an options provider lists.
    public convenience init<OptionsProvider: DynamicOptionsProvider>(
        title: LocalizedStringResource = "", description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil,
        requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil,
        inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: OptionsProvider) {
        self.init(title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog)
    }

    /// An entity parameter whose entities a query other than the entity's default one finds.
    public convenience init<Query: EntityQuery>(
        title: LocalizedStringResource = "", description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil,
        requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil,
        inputConnectionBehavior: InputConnectionBehavior = .default, query: Query) {
        self.init(title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog)
    }

    /// Whether the parameter may be empty: its type is optional.
    public var isOptional: Bool { Value.self is any _OptionalIntentValue.Type }

    /// The parameter itself, for `$account.needsValueError()`.
    public var projectedValue: IntentParameter<Value> { self }

    /// The parameter's value: what the app set, else the default, else nil for an optional.
    public var wrappedValue: Value {
        get { value ?? emptyValue(default: defaultValue, title: title, kind: "Parameter") }
        set { value = newValue }
    }

    public var valueState: ValueState {
        if let value { return .set(value) }
        if let defaultValue, let value = defaultValue as? Value { return .set(value) }
        return .unset
    }

    /// The error that tells the system to ask for this parameter. Nothing asks on the web: the
    /// intent ends with this error.
    public func needsValueError(_ dialog: IntentDialog? = nil) -> AppIntentError {
        AppIntentError(.needsValue(title, dialog ?? requestValueDialog))
    }

    /// Asks the user for a value. There is no one to ask on the web, so this throws.
    public func requestValue(_ dialog: IntentDialog? = nil) async throws -> Value.ValueType {
        throw needsValueError(dialog)
    }

    /// Asks the user to pick one of several values. There is no one to ask on the web, so this
    /// throws.
    public func requestDisambiguation(among itemsToDisambiguate: [Value.ValueType], dialog: IntentDialog? = nil) async throws -> Value.ValueType {
        throw AppIntentError(.unanswered(title))
    }

    /// Asks the user to confirm a value. There is no one to ask on the web, so this throws.
    public func requestConfirmation(for itemToConfirm: Value.ValueType, dialog: IntentDialog? = nil) async throws -> Bool {
        throw AppIntentError(.unanswered(title))
    }
}

extension IntentParameter.ValueState: Equatable where Value: Equatable {}

/// A property of an entity that Shortcuts can show and filter by:
/// `@Property(title: "Name") var name: String`.
@propertyWrapper
public final class EntityProperty<Value: _IntentValue & Sendable>: AnyIntentValue, @unchecked Sendable {
    public var title: LocalizedStringResource
    private var value: Value?

    public init() { title = "" }
    public init(title: LocalizedStringResource) { self.title = title }
    public init(identifier: String) { title = LocalizedStringResource(stringLiteral: identifier) }
    public init(identifier: String, title: LocalizedStringResource) { self.title = title }

    public var isOptional: Bool { Value.self is any _OptionalIntentValue.Type }
    public var projectedValue: EntityProperty<Value> { self }

    public var wrappedValue: Value {
        get { value ?? emptyValue(default: nil, title: title, kind: "Property") }
        set { value = newValue }
    }
}

/// Another intent's parameters, which a query reads to narrow its results while Shortcuts edits
/// that intent. No intent is being edited on the web, so it is always nil.
@propertyWrapper
public final class IntentParameterDependency<Intent: AppIntent>: @unchecked Sendable {
    public init() {}
    public init(_ keyPaths: PartialKeyPath<Intent>...) {}
    public var wrappedValue: IntentProjection<Intent>? { nil }
}

/// The parameters of an intent being edited, read through `dependency?.parameterName`.
@dynamicMemberLookup
public final class IntentProjection<Intent: AppIntent> {
    private let intent: Intent
    init(_ intent: Intent) { self.intent = intent }
    public subscript<Value>(dynamicMember keyPath: KeyPath<Intent, Value>) -> Value { intent[keyPath: keyPath] }
}

/// Whether Shortcuts may feed the previous action's result into a parameter.
public enum InputConnectionBehavior: Hashable, Sendable {
    case `default`
    case never
    case connectToPreviousIntentResult
}

/// How many values a collection parameter takes.
public struct IntentCollectionSize: ExpressibleByIntegerLiteral, Equatable, Sendable {
    public let min: Int
    public let max: Int
    public init(min: Int, max: Int) { self.min = min; self.max = max }
    public init(exactly: Int) { self.init(min: exactly, max: exactly) }
    public init(integerLiteral value: Int) { self.init(min: 1, max: value) }
}

/// What Siri says or shows in a conversation.
public struct IntentDialog: ExpressibleByStringInterpolation, Sendable {
    /// What Siri says.
    public let full: LocalizedStringResource
    /// A shorter version shown beside a snippet.
    public let supporting: LocalizedStringResource?
    /// A symbol shown with it.
    public let systemImageName: String?

    public init(_ string: LocalizedStringResource) { self.init(full: string, supporting: nil, image: nil) }
    public init(full: LocalizedStringResource, supporting: LocalizedStringResource) { self.init(full: full, supporting: supporting, image: nil) }
    public init(full: LocalizedStringResource, systemImageName: String) { self.init(full: full, supporting: nil, image: systemImageName) }
    public init(full: LocalizedStringResource, supporting: LocalizedStringResource, systemImageName: String) { self.init(full: full, supporting: supporting, image: systemImageName) }
    public init(stringLiteral value: String) { self.init(LocalizedStringResource(stringLiteral: value)) }
    public init(stringInterpolation: DefaultStringInterpolation) { self.init(LocalizedStringResource(stringLiteral: String(stringInterpolation: stringInterpolation))) }

    private init(full: LocalizedStringResource, supporting: LocalizedStringResource?, image: String?) {
        self.full = full
        self.supporting = supporting
        systemImageName = image
    }
}

/// An intent's description in Shortcuts.
public struct IntentDescription: ExpressibleByStringLiteral, @unchecked Sendable {
    public var descriptionText: LocalizedStringResource
    public var categoryName: LocalizedStringResource?
    public var searchKeywords: [LocalizedStringResource]
    public var resultValueName: LocalizedStringResource?

    public init(_ descriptionText: LocalizedStringResource, categoryName: LocalizedStringResource? = nil, searchKeywords: [LocalizedStringResource] = []) {
        self.init(descriptionText, categoryName: categoryName, searchKeywords: searchKeywords, resultValueName: nil)
    }

    public init(_ descriptionText: LocalizedStringResource, categoryName: LocalizedStringResource? = nil, searchKeywords: [LocalizedStringResource] = [], resultValueName: LocalizedStringResource?) {
        self.descriptionText = descriptionText
        self.categoryName = categoryName
        self.searchKeywords = searchKeywords
        self.resultValueName = resultValueName
    }

    public init(stringLiteral value: String) { self.init(LocalizedStringResource(stringLiteral: value)) }
}

/// An error an intent's run ends with.
public struct AppIntentError: Error, CustomStringConvertible, Sendable {
    enum Reason: Sendable {
        case restartPerform
        case needsValue(LocalizedStringResource, IntentDialog?)
        case unanswered(LocalizedStringResource)
    }

    let reason: Reason
    init(_ reason: Reason) { self.reason = reason }

    /// Asks the system to run the intent again from the start.
    public static var restartPerform: AppIntentError { AppIntentError(.restartPerform) }

    public var description: String {
        switch reason {
        case .restartPerform: "The intent asked to restart."
        case .needsValue(let title, let dialog): "The intent needs a value for '\(title.key)'" + (dialog.map { ": \($0.full.key)" } ?? ".")
        case .unanswered(let title): "There is no one to ask about '\(title.key)' on the web."
        }
    }
}
