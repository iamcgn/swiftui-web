// The tip an app declares, its parameters and events, and the rules over them.
import WebFoundation
import SwiftUI

/// A tip: what it says, and when it may show.
public protocol Tip: Identifiable, Sendable where ID == String {
    /// The tip's identifier (its type's name unless the tip gives one).
    var id: String { get }
    var title: Text { get }
    var message: Text? { get }
    var image: Image? { get }
    @Tips.ActionBuilder var actions: [Tips.Action] { get }
    @Tips.RuleBuilder var rules: [Tips.Rule] { get }
    @Tips.OptionsBuilder var options: [any TipOption] { get }
}

extension Tip {
    public typealias Action = Tips.Action
    public typealias Rule = Tips.Rule
    public typealias Option = TipOption
    public typealias Event<DonationInfo: Codable & Sendable> = Tips.Event<DonationInfo>
    public typealias MaxDisplayCount = Tips.MaxDisplayCount
    public typealias IgnoresDisplayFrequency = Tips.IgnoresDisplayFrequency
    public typealias MaxDisplayDuration = Tips.MaxDisplayDuration
    public typealias Status = Tips.Status
    public typealias InvalidationReason = Tips.InvalidationReason

    public var id: String { String(reflecting: Self.self) }
    public var message: Text? { nil }
    public var image: Image? { nil }
    public var actions: [Tips.Action] { [] }
    public var rules: [Tips.Rule] { [] }
    public var options: [any TipOption] { [] }

    /// Where the tip stands.
    public var status: Tips.Status { _TipStore.shared.status(of: self) }
    /// Whether the tip may show now.
    public var shouldDisplay: Bool { status == .available }

    /// The tip's status as it changes (its current status first).
    public var statusUpdates: AsyncStream<Tips.Status> {
        let tip = self
        return _TipStore.shared.updates { tip.status }
    }
    /// Whether the tip may show, as it changes (its current value first).
    public var shouldDisplayUpdates: AsyncStream<Bool> {
        let tip = self
        return _TipStore.shared.updates { tip.shouldDisplay }
    }

    /// Stops the tip from showing again.
    public func invalidate(reason: Tips.InvalidationReason) {
        _TipStore.shared.invalidate(id, reason: reason)
    }

    /// Lets an invalidated tip show again when its rules hold (its display count starts over).
    public func resetEligibility() async {
        _TipStore.shared.resetEligibility(id)
    }
}

extension Tips {
    /// A value a tip's rules read, kept by TipKit (`@Parameter static var isLoggedIn = false`).
    public final class Parameter<Value: Codable & Sendable>: @unchecked Sendable {
        /// The parameter's identifier.
        public let id: String
        let defaultValue: Value
        let transient: Bool

        public init(_ owner: Any.Type, _ name: String, _ defaultValue: Value, _ options: ParameterOption...) {
            id = "\(String(reflecting: owner)).\(name)"
            self.defaultValue = defaultValue
            transient = options.contains { $0.transient }
        }

        public init(id: String, _ defaultValue: Value, _ options: ParameterOption...) {
            self.id = id
            self.defaultValue = defaultValue
            transient = options.contains { $0.transient }
        }

        /// The parameter's value (its default until the app sets one).
        public var wrappedValue: Value {
            get { _TipStore.shared.parameter(id, as: Value.self) ?? defaultValue }
            set { _TipStore.shared.setParameter(id, newValue, transient: transient) }
        }
        /// The parameter's value.
        public var value: Value {
            get { wrappedValue }
            set { wrappedValue = newValue }
        }
    }

    /// How a parameter is kept.
    public struct ParameterOption: Sendable {
        let transient: Bool
        /// Kept only while the app runs, starting from its default at each launch.
        public static let transient = ParameterOption(transient: true)
    }

    /// Something the person does, which the app donates and a tip's rules count.
    public struct Event<DonationInfo: Codable & Sendable>: Identifiable, Sendable {
        /// One donation: when it happened and what came with it.
        @dynamicMemberLookup
        public struct Donation: Sendable {
            public let date: Date
            public let info: DonationInfo
            public subscript<T>(dynamicMember keyPath: KeyPath<DonationInfo, T>) -> T { info[keyPath: keyPath] }
        }

        public let id: String

        public init(id: String) { self.id = id }

        /// The event's donations, oldest first.
        public var donations: [Donation] {
            _TipStore.shared.donations(id).compactMap { record in
                guard let info = try? JSONDecoder().decode(DonationInfo.self, from: record.info) else { return nil }
                return Donation(date: record.date, info: info)
            }
        }

        /// Records that the event happened now, with what came with it.
        public func donate(_ donation: DonationInfo) { record(donation) }
        /// Records that the event happened now, with what came with it.
        public func donate(_ donation: DonationInfo) async { record(donation) }
        /// Records that the event happened now, with what came with it.
        public func sendDonation(_ donation: DonationInfo) async { record(donation) }

        func record(_ info: DonationInfo) {
            let data = (try? JSONEncoder().encode(info)) ?? Data()
            _TipStore.shared.donate(id, info: data)
        }
    }

    /// A span of time back from now, to count recent donations in.
    public struct DonationTimeRange: Hashable, Sendable {
        let seconds: TimeInterval
        public static let minute = DonationTimeRange(seconds: 60)
        public static let hour = DonationTimeRange(seconds: 3600)
        public static let day = DonationTimeRange(seconds: 86_400)
        public static let week = DonationTimeRange(seconds: 604_800)
        public static func minutes(_ count: Int) -> DonationTimeRange { DonationTimeRange(seconds: 60 * Double(count)) }
        public static func hours(_ count: Int) -> DonationTimeRange { DonationTimeRange(seconds: 3600 * Double(count)) }
        public static func days(_ count: Int) -> DonationTimeRange { DonationTimeRange(seconds: 86_400 * Double(count)) }
        public static func weeks(_ count: Int) -> DonationTimeRange { DonationTimeRange(seconds: 604_800 * Double(count)) }
    }

    /// A condition a tip waits for (`#Rule(Self.$isLoggedIn) { $0 == true }`).
    public struct Rule: @unchecked Sendable {
        let holds: () -> Bool

        public init<Value>(_ parameter: Parameter<Value>, _ body: @escaping (Value) -> Bool) {
            holds = { body(parameter.wrappedValue) }
        }
        public init<DonationInfo>(_ event: Event<DonationInfo>, _ body: @escaping (Event<DonationInfo>) -> Bool) {
            holds = { body(event) }
        }
    }
}

extension Tips.Event where DonationInfo == Tips.EmptyDonation {
    public init(id: String) { self.id = id }
    /// Records that the event happened now.
    public func donate() { record(Tips.EmptyDonation()) }
    /// Records that the event happened now.
    public func donate() async { record(Tips.EmptyDonation()) }
    /// Records that the event happened now.
    public func sendDonation() async { record(Tips.EmptyDonation()) }
}

extension Array {
    /// The donations made within the time range before now.
    public func donatedWithin<Info>(_ range: Tips.DonationTimeRange) -> [Tips.Event<Info>.Donation] where Element == Tips.Event<Info>.Donation {
        let start = Date().addingTimeInterval(-range.seconds)
        return filter { $0.date >= start }
    }
}

/// A value a tip's rules read: `@Parameter static var isLoggedIn: Bool = false` keeps it in TipKit
/// and adds `$isLoggedIn` for the rules.
@attached(accessor)
@attached(peer, names: prefixed(`$`))
public macro Parameter(_ options: Tips.ParameterOption...) = #externalMacro(module: "TipKitMacros", type: "ParameterMacro")

/// A condition a tip waits for: `#Rule(Self.$isLoggedIn) { $0 == true }`, or over an event,
/// `#Rule(Self.didOpenDetail) { $0.donations.count >= 3 }`.
@freestanding(expression)
public macro Rule<Value>(_ input: Tips.Parameter<Value>, _ body: (Value) -> Bool) -> Tips.Rule = #externalMacro(module: "TipKitMacros", type: "RuleMacro")
@freestanding(expression)
public macro Rule<DonationInfo>(_ input: Tips.Event<DonationInfo>, _ body: (Tips.Event<DonationInfo>) -> Bool) -> Tips.Rule = #externalMacro(module: "TipKitMacros", type: "RuleMacro")
