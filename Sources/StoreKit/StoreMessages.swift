// StoreKit's messages: notices the App Store has for the customer (a subscription's price
// increase to consent to, a billing issue, a win-back offer), which an app defers and then
// displays in a window scene (RevenueCat's `StoreMessagesHelper`). The web has no App Store to
// send any, so the sequence of messages ends without one.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// A message from the App Store that an app displays to the customer.
public struct Message: Hashable, Sendable {
    /// Why the App Store sent the message.
    public struct Reason: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public var description: String { rawValue }

        /// A message of no more particular kind.
        public static let generic = Reason(rawValue: "generic")
        /// The customer is asked to consent to a subscription's price increase.
        public static let priceIncreaseConsent = Reason(rawValue: "priceIncreaseConsent")
        /// A billing issue with the customer's subscription.
        public static let billingIssue = Reason(rawValue: "billingIssue")
        /// An offer to win back a lapsed subscriber.
        public static let winBackOffer = Reason(rawValue: "winBackOffer")
    }

    /// Why the App Store sent the message.
    public let reason: Reason

    /// Displays the message over the scene. There are no messages on the web to display.
    @MainActor public func display(in scene: UIWindowScene) throws {}

    /// The messages the App Store sends while the app runs: none on the web, so iterating
    /// them ends at once.
    public static var messages: Messages { Messages() }

    /// An asynchronous sequence of the App Store's messages.
    public struct Messages: AsyncSequence, Sendable {
        public typealias Element = Message
        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> Message? { nil }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }
}

/// The action that displays an App Store message (`@Environment(\.displayStoreKitMessage)`):
/// FoodTruck's and RevenueCat's message managers keep it and call it with each message the
/// sequence delivers. The web has no messages, so a call shows nothing.
public struct DisplayMessageAction: Sendable {
    package init() {}

    /// Displays the message.
    @MainActor public func callAsFunction(_ message: Message) throws {}
}

extension EnvironmentValues {
    /// The action that displays an App Store message.
    public var displayStoreKitMessage: DisplayMessageAction { DisplayMessageAction() }
}
