// The intent itself, what it returns, and how Shortcuts summarizes its parameters.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// An action the app offers to Siri, Shortcuts, widgets and its own buttons.
public protocol AppIntent: PersistentlyIdentifiable, _SupportsAppDependencies, Sendable {
    associatedtype PerformResult: IntentResult
    associatedtype SummaryContent: ParameterSummary

    /// The intent's name, as Shortcuts shows it.
    static var title: LocalizedStringResource { get }
    /// Whether running the intent brings the app to the front.
    static var openAppWhenRun: Bool { get }
    /// Where the intent can run (in the background, in the app).
    static var supportedModes: IntentModes { get }
    /// Whether the device must be unlocked to run it.
    static var authenticationPolicy: IntentAuthenticationPolicy { get }
    /// Whether Shortcuts and Spotlight list the intent.
    static var isDiscoverable: Bool { get }
    /// The sentence Shortcuts shows for the intent, with its parameters in place.
    static var parameterSummary: Self.SummaryContent { get }
    /// What the intent does.
    static var description: IntentDescription? { get }

    /// Does the work.
    func perform() async throws -> Self.PerformResult
    init()
}

extension AppIntent {
    public typealias Parameter = IntentParameter
    public typealias When = ParameterSummaryWhenCondition
    public typealias Switch<Value: _IntentValue & Sendable, CaseCondition: _ParameterSummarySwitchCase> = ParameterSummarySwitchCondition<Self, Value, CaseCondition>
    public typealias Case = ParameterSummaryCaseCondition
    public typealias DefaultCase = ParameterSummaryDefaultCaseCondition
    public typealias Summary = IntentParameterSummary<Self>
    public typealias Option = IntentChoiceOption

    public static var openAppWhenRun: Bool { false }
    public static var supportedModes: IntentModes { openAppWhenRun ? .foreground : .background }
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    public static var isDiscoverable: Bool { true }
    public static var description: IntentDescription? { nil }
    public static var parameterSummary: some ParameterSummary { IntentParameterSummary<Self>() }

    /// Offers the intent to Siri's suggestions. Nothing learns from donations on the web.
    @discardableResult
    public func donate() async throws -> IntentDonationIdentifier { IntentDonationIdentifier() }
    @discardableResult
    public func donate() -> IntentDonationIdentifier { IntentDonationIdentifier() }
    @discardableResult
    public func donate(result: some IntentResult) async throws -> IntentDonationIdentifier { IntentDonationIdentifier() }
    @discardableResult
    public func donate(result: some IntentResult) -> IntentDonationIdentifier { IntentDonationIdentifier() }

    /// Runs the intent and answers its value.
    public func callAsFunction(donate donateOnCompletion: Bool = true) async throws -> Self.PerformResult.Value where Self.PerformResult: ReturnsValue {
        guard let value = try await perform().value else { throw AppIntentError(.unanswered(Self.title)) }
        return value
    }

    /// Runs the intent.
    public func callAsFunction(donate donateOnCompletion: Bool = true) async throws where Self.PerformResult.Value == Never {
        _ = try await perform()
    }

    /// Asks the user to confirm before going on. There is no one to ask on the web, so this
    /// throws.
    public func requestConfirmation() async throws {
        throw AppIntentError(.unanswered(Self.title))
    }

    /// Asks the user to confirm, with a dialog. There is no one to ask on the web, so this throws.
    public func requestConfirmation(conditions: ConfirmationConditions = [], actionName: ConfirmationActionName = .continue, dialog: IntentDialog) async throws {
        throw AppIntentError(.unanswered(Self.title))
    }

    /// Asks the user to pick one of several options. There is no one to ask on the web, so this
    /// throws.
    public func requestChoice(between options: [IntentChoiceOption], dialog: IntentDialog? = nil) async throws -> IntentChoiceOption {
        throw AppIntentError(.unanswered(Self.title))
    }
}

extension Never: AppIntent {
    public typealias PerformResult = IntentResultContainer<Never, Never, Never, Never>
    public static var title: LocalizedStringResource { "" }
    public init() { fatalError("Never has no values") }
    public func perform() async throws -> IntentResultContainer<Never, Never, Never, Never> {
        switch self {}
    }
}

/// An intent that configures a widget: its parameters are the widget's settings.
public protocol WidgetConfigurationIntent: AppIntent {}

/// An intent that configures a control in Control Center.
public protocol ControlConfigurationIntent: AppIntent {}

/// An intent that performs one of the system's own actions.
public protocol SystemIntent: AppIntent {}

/// An intent that starts or updates a Live Activity.
public protocol LiveActivityIntent: SystemIntent {}

/// An intent that plays audio.
public protocol AudioPlaybackIntent: SystemIntent {}

/// An intent that can ask to continue in the app.
public protocol ForegroundContinuableIntent: AppIntent {}

/// An intent that reports its progress.
public protocol ProgressReportingIntent: AppIntent {}

/// An intent that sets a value (a toggle's state).
public protocol SetValueIntent<ValueType>: AppIntent {
    associatedtype ValueType: _IntentValue
    var value: Self.ValueType { get set }
}

/// An intent that opens an entity in the app.
public protocol OpenIntent: SystemIntent {
    associatedtype Value: AppValue
    var target: Self.Value { get set }
}

extension OpenIntent {
    public static var openAppWhenRun: Bool { true }
}

/// An intent that shows a snippet view.
public protocol SnippetIntent: AppIntent where Self.PerformResult: ShowsSnippetView {}

/// When Siri asks to confirm an intent.
public struct ConfirmationConditions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
}

/// The verb on a confirmation's button.
public struct ConfirmationActionName: Sendable {
    let name: String
    public static var `continue`: ConfirmationActionName { ConfirmationActionName(name: "Continue") }
    public static var add: ConfirmationActionName { ConfirmationActionName(name: "Add") }
    public static var buy: ConfirmationActionName { ConfirmationActionName(name: "Buy") }
    public static var go: ConfirmationActionName { ConfirmationActionName(name: "Go") }
    public static var order: ConfirmationActionName { ConfirmationActionName(name: "Order") }
    public static var post: ConfirmationActionName { ConfirmationActionName(name: "Post") }
    public static var run: ConfirmationActionName { ConfirmationActionName(name: "Run") }
    public static var send: ConfirmationActionName { ConfirmationActionName(name: "Send") }
    public static var set: ConfirmationActionName { ConfirmationActionName(name: "Set") }
    public static var start: ConfirmationActionName { ConfirmationActionName(name: "Start") }
    public static func custom(acceptLabel: LocalizedStringResource, acceptAlternatives: [LocalizedStringResource] = [], denyLabel: LocalizedStringResource, denyAlternatives: [LocalizedStringResource] = [], destructive: Bool = false) -> ConfirmationActionName {
        ConfirmationActionName(name: acceptLabel.key)
    }
}

/// An option offered by `requestChoice(between:dialog:)`.
public struct IntentChoiceOption: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case `default`
        case destructive
        case cancel
    }

    public let title: LocalizedStringResource
    public let style: Style

    public init(title: LocalizedStringResource, style: Style = .default) {
        self.title = title
        self.style = style
    }

    public static var cancel: IntentChoiceOption { IntentChoiceOption(title: "Cancel", style: .cancel) }
}

/// The identifier of a donation.
public struct IntentDonationIdentifier: Hashable, Codable, Sendable {
    let id: UUID
    init() { id = UUID() }
}

/// Whether running an intent needs an unlocked device.
public enum IntentAuthenticationPolicy: Hashable, Sendable {
    case alwaysAllowed
    case requiresAuthentication
    case requiresLocalDeviceAuthentication
}

/// Where an intent can run.
public struct IntentModes: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static var background: IntentModes { IntentModes(rawValue: 1) }
    public static var foreground: IntentModes { IntentModes(rawValue: 2) }
    public static func foreground(_ foregroundMode: ForegroundMode) -> IntentModes { .foreground }

    /// When an intent comes to the front.
    public struct ForegroundMode: Hashable, Sendable {
        let rawValue: Int
        public static var immediate: ForegroundMode { ForegroundMode(rawValue: 0) }
        public static var deferred: ForegroundMode { ForegroundMode(rawValue: 1) }
        public static var dynamic: ForegroundMode { ForegroundMode(rawValue: 2) }
    }
}

// MARK: Results

/// What an intent's `perform()` returns: a value, a dialog, a snippet view.
public protocol IntentResult: Sendable {
    associatedtype Value: _IntentValue = Never
    associatedtype Snippet = Never
    associatedtype Dialog = Never
    associatedtype OpensAppIntent: AppIntent = Never
    var value: Self.Value? { get }
}

public protocol ReturnsValue<Value>: IntentResult {}
public protocol OpensIntent: IntentResult {}
public protocol ProvidesDialog: IntentResult where Self.Dialog == IntentDialog {}
public protocol ShowsSnippetView: IntentResult where Self.Snippet == _SnippetViewContainer {}
public protocol ShowsSnippetIntent: IntentResult where Self.Snippet == _SnippetIntentContainer {}

extension Never: IntentResult {
    public var value: Never? { nil }
}

/// A view an intent shows as its result.
public struct _SnippetViewContainer: @unchecked Sendable {
    /// The view.
    public let view: AnyView
}

/// An intent whose view an intent shows as its result.
public struct _SnippetIntentContainer: Sendable {}

/// The result `.result(...)` makes.
public struct IntentResultContainer<Value: _IntentValue, OpensAppIntent: AppIntent, Snippet, Dialog>: IntentResult, @unchecked Sendable {
    public var value: Value?
    public var dialog: IntentDialog?
    public var opensIntent: OpensAppIntent?
    public var activityIdentifier: String?
    /// The snippet view, for a result that shows one.
    public var snippet: _SnippetViewContainer?

    init(value: Value? = nil, dialog: IntentDialog? = nil, opensIntent: OpensAppIntent? = nil, snippet: _SnippetViewContainer? = nil) {
        self.value = value
        self.dialog = dialog
        self.opensIntent = opensIntent
        self.snippet = snippet
    }
}

extension IntentResultContainer: ReturnsValue {}
extension IntentResultContainer: OpensIntent {}
extension IntentResultContainer: ProvidesDialog where Dialog == IntentDialog {}
extension IntentResultContainer: ShowsSnippetView where Snippet == _SnippetViewContainer {}
extension IntentResultContainer: ShowsSnippetIntent where Snippet == _SnippetIntentContainer {}

extension IntentResult {
    public static func result() -> Self where Self == IntentResultContainer<Never, Never, Never, Never> { .init() }

    public static func result<Value: _IntentValue>(value: Value) -> Self where Self == IntentResultContainer<Value, Never, Never, Never> { .init(value: value) }

    public static func result<OpensAppIntent: AppIntent>(opensIntent: OpensAppIntent) -> Self where Self == IntentResultContainer<Never, OpensAppIntent, Never, Never> { .init(opensIntent: opensIntent) }

    public static func result(dialog: IntentDialog) -> Self where Self == IntentResultContainer<Never, Never, Never, IntentDialog> { .init(dialog: dialog) }

    public static func result<Value: _IntentValue, OpensAppIntent: AppIntent>(value: Value, opensIntent: OpensAppIntent) -> Self where Self == IntentResultContainer<Value, OpensAppIntent, Never, Never> {
        .init(value: value, opensIntent: opensIntent)
    }

    public static func result<Value: _IntentValue>(value: Value, dialog: IntentDialog) -> Self where Self == IntentResultContainer<Value, Never, Never, IntentDialog> {
        .init(value: value, dialog: dialog)
    }

    public static func result<Value: _IntentValue, OpensAppIntent: AppIntent>(value: Value, opensIntent: OpensAppIntent, dialog: IntentDialog) -> Self where Self == IntentResultContainer<Value, OpensAppIntent, Never, IntentDialog> {
        .init(value: value, dialog: dialog, opensIntent: opensIntent)
    }

    public static func result<OpensAppIntent: AppIntent>(opensIntent: OpensAppIntent, dialog: IntentDialog) -> Self where Self == IntentResultContainer<Never, OpensAppIntent, Never, IntentDialog> {
        .init(dialog: dialog, opensIntent: opensIntent)
    }

    // The snippet-view results (Apple's SwiftUI overlay).

    public static func result<Content: View>(@ViewBuilder content: () -> Content) -> Self where Self == IntentResultContainer<Never, Never, _SnippetViewContainer, Never> {
        .init(snippet: _SnippetViewContainer(view: AnyView(content())))
    }

    public static func result<Content: View>(view: Content) -> Self where Self == IntentResultContainer<Never, Never, _SnippetViewContainer, Never> {
        .init(snippet: _SnippetViewContainer(view: AnyView(view)))
    }

    public static func result<Content: View>(dialog: IntentDialog, @ViewBuilder content: () -> Content) -> Self where Self == IntentResultContainer<Never, Never, _SnippetViewContainer, IntentDialog> {
        .init(dialog: dialog, snippet: _SnippetViewContainer(view: AnyView(content())))
    }

    public static func result<Content: View>(dialog: IntentDialog, view: Content) -> Self where Self == IntentResultContainer<Never, Never, _SnippetViewContainer, IntentDialog> {
        .init(dialog: dialog, snippet: _SnippetViewContainer(view: AnyView(view)))
    }

    public static func result<Value: _IntentValue, Content: View>(value: Value, @ViewBuilder content: () -> Content) -> Self where Self == IntentResultContainer<Value, Never, _SnippetViewContainer, Never> {
        .init(value: value, snippet: _SnippetViewContainer(view: AnyView(content())))
    }

    public static func result<Value: _IntentValue, Content: View>(value: Value, view: Content) -> Self where Self == IntentResultContainer<Value, Never, _SnippetViewContainer, Never> {
        .init(value: value, snippet: _SnippetViewContainer(view: AnyView(view)))
    }

    public static func result<Value: _IntentValue, Content: View>(value: Value, dialog: IntentDialog, @ViewBuilder content: () -> Content) -> Self where Self == IntentResultContainer<Value, Never, _SnippetViewContainer, IntentDialog> {
        .init(value: value, dialog: dialog, snippet: _SnippetViewContainer(view: AnyView(content())))
    }

    public static func result<Value: _IntentValue, Content: View>(value: Value, dialog: IntentDialog, view: Content) -> Self where Self == IntentResultContainer<Value, Never, _SnippetViewContainer, IntentDialog> {
        .init(value: value, dialog: dialog, snippet: _SnippetViewContainer(view: AnyView(view)))
    }
}

// MARK: Parameter summaries

/// The sentence Shortcuts shows for an intent, with its parameters in place.
public protocol ParameterSummary {
    associatedtype Intent: AppIntent
}

extension Never: ParameterSummary {
    public typealias Intent = Never
}

@resultBuilder
public enum ParameterSummaryBuilder<Intent: AppIntent> {
    public static func buildExpression<Summary: ParameterSummary>(_ expression: Summary) -> Summary where Intent == Summary.Intent { expression }
    public static func buildBlock<Summary: ParameterSummary>(_ block: Summary) -> Summary where Intent == Summary.Intent { block }
}

/// A summary sentence: `Summary("Send \(\.$message) to \(\.$person)")`.
public struct IntentParameterSummary<Intent: AppIntent>: ParameterSummary {
    /// The sentence, with each parameter's title in place.
    public let text: String
    /// The parameters listed under the sentence.
    public let additionalParameters: [PartialKeyPath<Intent>]

    public init(_ string: ParameterSummaryString<Intent>, table: String? = nil, @ParameterKeyPathsBuilder _ additionalParameterKeyPaths: () -> [PartialKeyPath<Intent>]) {
        text = string.text
        additionalParameters = additionalParameterKeyPaths()
    }

    public init(_ string: ParameterSummaryString<Intent>, table: String? = nil) {
        text = string.text
        additionalParameters = []
    }

    public init(@ParameterKeyPathsBuilder _ additionalParameterKeyPaths: () -> [PartialKeyPath<Intent>]) {
        text = ""
        additionalParameters = additionalParameterKeyPaths()
    }

    public init() {
        text = ""
        additionalParameters = []
    }

    @resultBuilder
    public enum ParameterKeyPathsBuilder {
        public static func buildExpression<ValueType: _IntentValue & Sendable>(_ expression: KeyPath<Intent, IntentParameter<ValueType>>) -> PartialKeyPath<Intent> { expression }
        public static func buildBlock(_ blocks: PartialKeyPath<Intent>...) -> [PartialKeyPath<Intent>] { blocks }
    }
}

/// A summary's text, with parameters interpolated by key path.
public struct ParameterSummaryString<Intent: AppIntent>: ExpressibleByStringInterpolation {
    let text: String

    public init(_ value: String) { text = value }
    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }

    public struct StringInterpolation: StringInterpolationProtocol {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { text += literal }
        public mutating func appendInterpolation<ValueType: _IntentValue & Sendable, Subject: KeyPath<Intent, IntentParameter<ValueType>>>(_ subject: Subject) {
            text += "${\(subject)}"
        }
    }
}

public enum HasValueComparisonOperator: Hashable, Sendable {
    case hasNoValue
    case hasAnyValue
}

public enum EquatableComparisonOperator: Hashable, Sendable {
    case notEqualTo
    case equalTo
}

public enum OneOfComparisonOperator: Hashable, Sendable {
    case oneOf
}

public enum ComparableComparisonOperator: Hashable, Sendable {
    case lessThan
    case lessThanOrEqualTo
    case greaterThan
    case greaterThanOrEqualTo
}

public enum StringComparisonOperator: Hashable, Sendable {
    case doesNotContain
    case contains
    case hasPrefix
    case hasSuffix
}

/// A summary that depends on a parameter's value: `When(\.$repeats, .equalTo, true) { ... }`.
public struct ParameterSummaryWhenCondition<Intent: AppIntent, WhenCondition: ParameterSummary, Otherwise: ParameterSummary>: ParameterSummary {
    /// The summary while the condition holds.
    public let whenSummary: WhenCondition
    /// The summary otherwise, when there is one.
    public let otherwiseSummary: Otherwise?

    public init<Parameter: AnyIntentValue>(_ keyPath: KeyPath<Intent, Parameter>, _ comparisonOperator: HasValueComparisonOperator,
                                           @ParameterSummaryBuilder<Intent> _ when: () -> WhenCondition,
                                           @ParameterSummaryBuilder<Intent> otherwise: () -> Otherwise) {
        whenSummary = when()
        otherwiseSummary = otherwise()
    }

    public init<ValueType: Equatable, Parameter: AnyIntentValue>(_ keyPath: KeyPath<Intent, Parameter>, _ comparisonOperator: EquatableComparisonOperator, _ value: ValueType,
                                                                 @ParameterSummaryBuilder<Intent> _ when: () -> WhenCondition,
                                                                 @ParameterSummaryBuilder<Intent> otherwise: () -> Otherwise) where ValueType == Parameter.Value {
        whenSummary = when()
        otherwiseSummary = otherwise()
    }

    public init<ValueType: Comparable, Parameter: AnyIntentValue>(_ keyPath: KeyPath<Intent, Parameter>, _ comparisonOperator: ComparableComparisonOperator, _ value: ValueType,
                                                                  @ParameterSummaryBuilder<Intent> _ when: () -> WhenCondition,
                                                                  @ParameterSummaryBuilder<Intent> otherwise: () -> Otherwise) where ValueType == Parameter.Value {
        whenSummary = when()
        otherwiseSummary = otherwise()
    }

    public init<ValueType, Parameter: AnyIntentValue>(_ keyPath: KeyPath<Intent, Parameter>, _ comparisonOperator: OneOfComparisonOperator, _ values: [ValueType],
                                                      @ParameterSummaryBuilder<Intent> _ when: () -> WhenCondition,
                                                      @ParameterSummaryBuilder<Intent> otherwise: () -> Otherwise) where ValueType == Parameter.Value.ValueType {
        whenSummary = when()
        otherwiseSummary = otherwise()
    }
}

extension ParameterSummaryWhenCondition where Otherwise == Never {
    public init<Parameter: AnyIntentValue>(_ keyPath: KeyPath<Intent, Parameter>, _ comparisonOperator: HasValueComparisonOperator,
                                           @ParameterSummaryBuilder<Intent> _ when: () -> WhenCondition) {
        whenSummary = when()
        otherwiseSummary = nil
    }

    public init<ValueType: Equatable, Parameter: AnyIntentValue>(_ keyPath: KeyPath<Intent, Parameter>, _ comparisonOperator: EquatableComparisonOperator, _ value: ValueType,
                                                                 @ParameterSummaryBuilder<Intent> _ when: () -> WhenCondition) where ValueType == Parameter.Value {
        whenSummary = when()
        otherwiseSummary = nil
    }
}

/// One case of a `Switch`.
public protocol _ParameterSummarySwitchCase {
    associatedtype Intent: AppIntent
    associatedtype Value: _IntentValue
    associatedtype Summary: ParameterSummary
}

/// A summary chosen by a parameter's value: `Switch(\.$kind) { Case(.a) { ... } DefaultCase { ... } }`.
public struct ParameterSummarySwitchCondition<Intent: AppIntent, Value: _IntentValue & Sendable, CaseCondition: _ParameterSummarySwitchCase>: ParameterSummary {
    public let cases: CaseCondition

    public init(_ keyPath: KeyPath<Intent, IntentParameter<Value>>, @ParameterSummaryCaseBuilder<Intent, Value> _ builder: () -> CaseCondition) {
        cases = builder()
    }
}

public struct ParameterSummaryCaseCondition<Intent: AppIntent, Value: _IntentValue, Summary: ParameterSummary>: _ParameterSummarySwitchCase {
    public let summary: Summary
    public init(_ value: Value, @ParameterSummaryBuilder<Intent> _ parameterSummary: () -> Summary) { summary = parameterSummary() }
    public init(_ value: [Value], @ParameterSummaryBuilder<Intent> _ parameterSummary: () -> Summary) { summary = parameterSummary() }
}

public struct ParameterSummaryDefaultCaseCondition<Intent: AppIntent, Value: _IntentValue, Summary: ParameterSummary>: _ParameterSummarySwitchCase {
    public let summary: Summary
    public init(@ParameterSummaryBuilder<Intent> _ parameterSummary: () -> Summary) { summary = parameterSummary() }
}

/// Several cases of a `Switch`, as one.
public struct ParameterSummaryTupleCaseCondition<Intent: AppIntent, Value: _IntentValue, ValueType>: _ParameterSummarySwitchCase {
    public typealias Summary = Never
    let cases: ValueType
}

@resultBuilder
public enum ParameterSummaryCaseBuilder<Intent: AppIntent, Value: _IntentValue> {
    public static func buildExpression<C0: _ParameterSummarySwitchCase>(_ expression: C0) -> C0 where Intent == C0.Intent, Value == C0.Value { expression }
    public static func buildBlock<each C: _ParameterSummarySwitchCase>(_ c: repeat each C) -> ParameterSummaryTupleCaseCondition<Intent, Value, (repeat each C)> {
        ParameterSummaryTupleCaseCondition(cases: (repeat each c))
    }
}
