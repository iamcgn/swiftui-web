// TipKit on the web: tips an app declares show inline (`TipView`) or in a popover (`popoverTip`)
// when the app has configured TipKit, their rules hold, they have not been closed or shown too
// often, and the display frequency allows a new tip. Parameters and event donations persist in
// the app's user defaults (the browser's storage for the page), so a closed tip stays closed after
// a reload. The datastore's location and CloudKit sync are accepted; a page keeps its datastore in
// that one place and syncs nothing.
@_exported import WebFoundation
import SwiftUI

/// TipKit's namespace: configuration, parameters, events, rules and options.
public enum Tips {
    // MARK: Configuration

    /// Loads the tips' datastore and starts showing eligible tips. Configuring twice throws.
    public static func configure(_ configuration: [ConfigurationOption] = []) throws {
        try _TipStore.shared.configure(configuration)
    }

    /// Erases every tip's state, parameter and donation. Call before `configure`.
    public static func resetDatastore() throws {
        _TipStore.shared.reset()
    }

    /// Shows every tip whatever its rules and state (for testing).
    public static func showAllTipsForTesting() { _TipStore.shared.setTesting(.showAll) }
    /// Shows these tips whatever their rules and state (for testing).
    public static func showTipsForTesting(_ tips: [any Tip.Type]) { _TipStore.shared.setTesting(.show(Set(tips.map { String(reflecting: $0) }))) }
    /// Hides every tip (for testing).
    public static func hideAllTipsForTesting() { _TipStore.shared.setTesting(.hideAll) }
    /// Hides these tips (for testing).
    public static func hideTipsForTesting(_ tips: [any Tip.Type]) { _TipStore.shared.setTesting(.hide(Set(tips.map { String(reflecting: $0) }))) }

    /// A setting `configure` takes.
    public struct ConfigurationOption: Sendable {
        enum Kind: Sendable {
            case displayFrequency(TimeInterval)
            case datastoreLocation
            case cloudKitContainer
        }
        let kind: Kind

        /// How often a new tip may appear.
        public struct DisplayFrequency: Hashable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
            let interval: TimeInterval
            public init(_ interval: TimeInterval) { self.interval = interval }
            public init(floatLiteral value: Double) { interval = value }
            public init(integerLiteral value: Int) { interval = TimeInterval(value) }
            /// Every eligible tip, as soon as it is.
            public static let immediate = DisplayFrequency(0)
            public static let hourly = DisplayFrequency(3600)
            public static let daily = DisplayFrequency(86_400)
            public static let weekly = DisplayFrequency(604_800)
            public static let monthly = DisplayFrequency(2_592_000)
        }

        /// Where the datastore lives (a page keeps it in its storage).
        public struct DatastoreLocation: Sendable {
            let description: String
            public static let applicationDefault = DatastoreLocation(description: "applicationDefault")
            public static func groupContainer(identifier: String) -> DatastoreLocation { DatastoreLocation(description: identifier) }
            public static func url(_ url: URL, shouldReset: Bool = false) -> DatastoreLocation { DatastoreLocation(description: url.absoluteString) }
            public init(url: URL, shouldReset: Bool = false) { description = url.absoluteString }
            public init(groupIdentifier: String, directoryName: String? = nil) throws { description = groupIdentifier }
            init(description: String) { self.description = description }
        }

        /// The CloudKit container the datastore syncs through (a page syncs nothing).
        public struct CloudKitContainerOption: Sendable {
            let name: String?
            public static let automatic = CloudKitContainerOption(name: nil)
            public static func named(_ name: String) -> CloudKitContainerOption { CloudKitContainerOption(name: name) }
        }

        public static func displayFrequency(_ frequency: DisplayFrequency) -> ConfigurationOption { ConfigurationOption(kind: .displayFrequency(frequency.interval)) }
        public static func displayFrequency(_ interval: TimeInterval) -> ConfigurationOption { ConfigurationOption(kind: .displayFrequency(interval)) }
        public static func datastoreLocation(_ location: DatastoreLocation) -> ConfigurationOption { ConfigurationOption(kind: .datastoreLocation) }
        public static func cloudKitContainer(_ container: CloudKitContainerOption) -> ConfigurationOption { ConfigurationOption(kind: .cloudKitContainer) }
    }

    // MARK: Status

    /// Where a tip stands.
    public enum Status: Hashable, Sendable {
        /// Its rules do not hold yet (or another tip took the display frequency's turn).
        case pending
        /// It may show.
        case available
        /// It will not show again.
        case invalidated(InvalidationReason)
    }

    /// Why a tip stopped showing.
    public enum InvalidationReason: Hashable, Sendable, Codable {
        /// The person did what the tip suggested.
        case actionPerformed
        /// It showed as many times as its `MaxDisplayCount` allows.
        case displayCountExceeded
        /// It showed for as long as its `MaxDisplayDuration` allows.
        case displayDurationExceeded
        /// The person closed it.
        case tipClosed
    }

    // MARK: Actions

    /// A button a tip shows below its message.
    public struct Action: Identifiable, Sendable {
        public let id: String
        public let index: Int?
        let title: Text?
        let handler: @Sendable () -> Void

        public init(id: String? = nil, title: String, perform handler: @escaping @Sendable () -> Void = {}) {
            self.id = id ?? title
            index = nil
            self.title = Text(title)
            self.handler = handler
        }
        public init(id: String? = nil, perform handler: @escaping @Sendable () -> Void = {}, _ label: () -> Text) {
            let text = label()
            self.id = id ?? UUID().uuidString
            index = nil
            title = text
            self.handler = handler
        }
        init(_ action: Action, index: Int) {
            id = action.id
            self.index = index
            title = action.title
            handler = action.handler
        }
    }

    // MARK: Options

    /// The most times a tip shows before it invalidates.
    public struct MaxDisplayCount: TipOption {
        public let count: Int
        public init(_ count: Int) { self.count = count }
    }
    /// Whether a tip shows whatever the display frequency.
    public struct IgnoresDisplayFrequency: TipOption {
        public let ignores: Bool
        public init(_ ignores: Bool) { self.ignores = ignores }
    }
    /// The longest a tip shows (in seconds, across its displays) before it invalidates.
    public struct MaxDisplayDuration: TipOption {
        public let duration: TimeInterval
        public init(_ duration: TimeInterval) { self.duration = duration }
    }

    // MARK: Builders

    @resultBuilder
    public enum RuleBuilder {
        public static func buildExpression(_ rule: Rule) -> [Rule] { [rule] }
        public static func buildExpression(_ rules: [Rule]) -> [Rule] { rules }
        public static func buildBlock(_ components: [Rule]...) -> [Rule] { components.flatMap { $0 } }
        public static func buildOptional(_ component: [Rule]?) -> [Rule] { component ?? [] }
        public static func buildEither(first component: [Rule]) -> [Rule] { component }
        public static func buildEither(second component: [Rule]) -> [Rule] { component }
        public static func buildArray(_ components: [[Rule]]) -> [Rule] { components.flatMap { $0 } }
        public static func buildLimitedAvailability(_ component: [Rule]) -> [Rule] { component }
    }

    @resultBuilder
    public enum OptionsBuilder {
        public static func buildExpression(_ option: any TipOption) -> [any TipOption] { [option] }
        public static func buildExpression(_ options: [any TipOption]) -> [any TipOption] { options }
        public static func buildBlock(_ components: [any TipOption]...) -> [any TipOption] { components.flatMap { $0 } }
        public static func buildOptional(_ component: [any TipOption]?) -> [any TipOption] { component ?? [] }
        public static func buildEither(first component: [any TipOption]) -> [any TipOption] { component }
        public static func buildEither(second component: [any TipOption]) -> [any TipOption] { component }
        public static func buildArray(_ components: [[any TipOption]]) -> [any TipOption] { components.flatMap { $0 } }
        public static func buildLimitedAvailability(_ component: [any TipOption]) -> [any TipOption] { component }
    }

    @resultBuilder
    public enum ActionBuilder {
        public static func buildExpression(_ action: Action) -> [Action] { [action] }
        public static func buildExpression(_ actions: [Action]) -> [Action] { actions }
        public static func buildBlock(_ components: [Action]...) -> [Action] { components.flatMap { $0 } }
        public static func buildOptional(_ component: [Action]?) -> [Action] { component ?? [] }
        public static func buildEither(first component: [Action]) -> [Action] { component }
        public static func buildEither(second component: [Action]) -> [Action] { component }
        public static func buildArray(_ components: [[Action]]) -> [Action] { components.flatMap { $0 } }
        public static func buildLimitedAvailability(_ component: [Action]) -> [Action] { component }
    }

    /// The donation of an event that carries no information.
    public struct EmptyDonation: Codable, Hashable, Sendable {
        public init() {}
    }
}

/// A setting of a tip (`MaxDisplayCount`, `IgnoresDisplayFrequency`, `MaxDisplayDuration`).
public protocol TipOption: Sendable {}

/// Why TipKit refused a call.
public struct TipKitError: Error, Hashable, Sendable, CustomStringConvertible {
    let code: Int
    public var description: String {
        code == 1 ? "TipKit's datastore is already configured." : "TipKit's datastore could not be reached."
    }
    /// `configure` was called after the datastore was configured.
    public static let tipsDatastoreAlreadyConfigured = TipKitError(code: 1)
    /// The datastore could not be read or written.
    public static let tipsDatastoreNotAvailable = TipKitError(code: 2)
}
