// App Shortcuts and the SwiftUI views that run intents. A web page has no Shortcuts app and no
// Siri, so the shortcuts an app declares are kept as values and never offered; the Siri tip and
// the link to Shortcuts show nothing. A button or toggle made with an intent runs the intent's
// `perform()` when pressed, as it does in an app on iOS.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// A word Siri fills into a phrase.
public enum AppShortcutPhraseToken: Hashable, Sendable {
    /// The app's name.
    case applicationName
}

/// A phrase that runs a shortcut: `"Start a workout in \(.applicationName)"`.
public struct AppShortcutPhrase<Intent: AppIntent>: ExpressibleByStringInterpolation {
    /// The phrase, with `${applicationName}` and each parameter's key path in place.
    public let text: String

    public init(_ value: String) { text = value }
    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }

    public struct StringInterpolation: StringInterpolationProtocol {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { text += literal }
        public mutating func appendInterpolation(_ token: AppShortcutPhraseToken) { text += "${applicationName}" }
        public mutating func appendInterpolation<Value: _IntentValue & Sendable, Subject: KeyPath<Intent, IntentParameter<Value>>>(_ subject: Subject) {
            text += "${\(subject)}"
        }
    }
}

/// A phrase that should not run a shortcut.
public struct NegativeAppShortcutPhrase: ExpressibleByStringInterpolation {
    public let text: String
    public init(_ value: String) { text = value }
    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }

    public struct StringInterpolation: StringInterpolationProtocol {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { text += literal }
        public mutating func appendInterpolation(_ token: AppShortcutPhraseToken) { text += "${applicationName}" }
    }
}

/// A shortcut the app offers without the user setting it up: an intent and its phrases.
public struct AppShortcut {
    /// The intent's type name.
    public let intentIdentifier: String
    /// The phrases, as text.
    public let phrases: [String]
    public let shortTitle: LocalizedStringResource?
    public let systemImageName: String?

    public init<Intent: AppIntent>(intent: Intent, phrases: [AppShortcutPhrase<Intent>], shortTitle: LocalizedStringResource? = nil, systemImageName: String? = nil) {
        intentIdentifier = Intent.persistentIdentifier
        self.phrases = phrases.map(\.text)
        self.shortTitle = shortTitle
        self.systemImageName = systemImageName
    }
}

/// Builds an app's list of shortcuts.
@resultBuilder
public enum AppShortcutsBuilder {
    public static func buildExpression(_ component: AppShortcut) -> [AppShortcut] { [component] }
    public static func buildBlock(_ components: [AppShortcut]...) -> [AppShortcut] { components.flatMap { $0 } }
    public static func buildBlock() -> [AppShortcut] { [] }
    public static func buildOptional(_ appShortcuts: [AppShortcut]?) -> [AppShortcut] { appShortcuts ?? [] }
    public static func buildEither(first component: [AppShortcut]) -> [AppShortcut] { component }
    public static func buildEither(second component: [AppShortcut]) -> [AppShortcut] { component }
    public static func buildArray(_ components: [[AppShortcut]]) -> [AppShortcut] { components.flatMap { $0 } }
    public static func buildLimitedAvailability(_ components: [AppShortcut]) -> [AppShortcut] { components }
}

/// The app's shortcuts. On iOS the system reads them at install; nothing reads them on the web.
public protocol AppShortcutsProvider: Sendable {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get }
    static var shortcutTileColor: ShortcutTileColor { get }
}

extension AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor { .navy }
    /// Tells Siri the shortcuts' parameter options changed. Nothing listens on the web.
    public static func updateAppShortcutParameters() {}
}

/// The color of an app's tiles in Shortcuts.
public enum ShortcutTileColor: Hashable, Sendable {
    case red, orange, tangerine, yellow, lime, teal, lightBlue, blue, navy, grape, purple, pink, grayBlue, grayGreen, grayBrown
}

/// The donations the app made, for deleting them. There are none on the web.
public struct IntentDonationManager: Sendable {
    public static var shared: IntentDonationManager { IntentDonationManager() }
    public func deleteDonations(matching predicate: IntentDonationMatchingPredicate) async throws {}
}

/// Which donations to delete.
public struct IntentDonationMatchingPredicate: Sendable {
    public static func intentType<Intent: AppIntent>(_ intentType: Intent.Type) -> IntentDonationMatchingPredicate { IntentDonationMatchingPredicate() }
    public static func donationIdentifiers(_ donationIdentifiers: [IntentDonationIdentifier]) -> IntentDonationMatchingPredicate { IntentDonationMatchingPredicate() }
}

// MARK: SwiftUI

/// Runs an intent for a button or toggle, dropping its result (a widget's button does too).
private func run<Intent: AppIntent>(_ intent: Intent) {
    Task { _ = try? await intent.perform() }
}

extension Button {
    /// A button that runs an intent.
    @preconcurrency nonisolated public init<Intent: AppIntent>(intent: Intent, @ViewBuilder label: () -> Label) {
        self.init(action: { run(intent) }, label: label)
    }

    /// A button with a role that runs an intent.
    @preconcurrency nonisolated public init<Intent: AppIntent>(role: ButtonRole?, intent: Intent, @ViewBuilder label: () -> Label) {
        self.init(role: role, action: { run(intent) }, label: label)
    }
}

extension Button where Label == Text {
    /// A button titled from a localized key that runs an intent.
    @preconcurrency nonisolated public init<Intent: AppIntent>(_ titleKey: LocalizedStringKey, intent: Intent) {
        self.init(titleKey, action: { run(intent) })
    }

    /// A button titled from a string that runs an intent.
    @_disfavoredOverload
    @preconcurrency nonisolated public init<S: StringProtocol, Intent: AppIntent>(_ title: S, intent: Intent) {
        self.init(title, action: { run(intent) })
    }
}

extension Toggle {
    /// A toggle that shows `isOn` and runs an intent when the user flips it.
    @MainActor
    public init<Intent: AppIntent>(isOn: Bool, intent: Intent, @ViewBuilder label: () -> Label) {
        self.init(isOn: Binding(get: { isOn }, set: { _ in run(intent) }), label: label)
    }
}

extension Toggle where Label == Text {
    /// A toggle titled from a localized key that runs an intent.
    @MainActor
    public init<Intent: AppIntent>(_ titleKey: LocalizedStringKey, isOn: Bool, intent: Intent) {
        self.init(isOn: isOn, intent: intent) { Text(titleKey) }
    }

    /// A toggle titled from a string that runs an intent.
    @_disfavoredOverload
    @MainActor
    public init<S: StringProtocol, Intent: AppIntent>(_ title: S, isOn: Bool, intent: Intent) {
        self.init(isOn: isOn, intent: intent) { Text(title) }
    }
}

/// A tip suggesting the phrase that runs an intent. Siri can't be asked on the web, so it shows
/// nothing.
public struct SiriTipView: View {
    public init<Intent: AppIntent>(intent: Intent, isVisible: Binding<Bool> = .constant(true)) {}
    public var body: some View { EmptyView() }
}

/// A link to the app's shortcuts in the Shortcuts app. There is no Shortcuts app on the web, so
/// it shows nothing.
public struct ShortcutsLink: View {
    public init(action: (() -> Void)? = nil) {}
    public var body: some View { EmptyView() }
}

/// The look of a Siri tip.
public struct SiriTipViewStyle: Hashable, Sendable {
    let name: String
    public static var automatic: SiriTipViewStyle { SiriTipViewStyle(name: "automatic") }
    public static var light: SiriTipViewStyle { SiriTipViewStyle(name: "light") }
    public static var dark: SiriTipViewStyle { SiriTipViewStyle(name: "dark") }
}

/// The look of a Shortcuts link.
public struct ShortcutsLinkStyle: Hashable, Sendable {
    let name: String
    public static var automatic: ShortcutsLinkStyle { ShortcutsLinkStyle(name: "automatic") }
    public static var automaticOutline: ShortcutsLinkStyle { ShortcutsLinkStyle(name: "automaticOutline") }
    public static var light: ShortcutsLinkStyle { ShortcutsLinkStyle(name: "light") }
    public static var lightOutline: ShortcutsLinkStyle { ShortcutsLinkStyle(name: "lightOutline") }
    public static var dark: ShortcutsLinkStyle { ShortcutsLinkStyle(name: "dark") }
    public static var darkOutline: ShortcutsLinkStyle { ShortcutsLinkStyle(name: "darkOutline") }
}

extension View {
    /// Sets the look of Siri tips inside: nothing to style on the web.
    public func siriTipViewStyle(_ style: SiriTipViewStyle) -> Self { self }
    /// Sets the look of Shortcuts links inside: nothing to style on the web.
    public func shortcutsLinkStyle(_ style: ShortcutsLinkStyle) -> Self { self }
}
