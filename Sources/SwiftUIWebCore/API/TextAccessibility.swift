// A text's own accessibility and speech modifiers, which return `Text` as SwiftUI's do
// (SwiftNavigation's `TextState` applies each to a `Text` and keeps a `Text`). A label and a
// heading level are what the text's element reads as; the content type and the speech hints
// are kept nowhere, as a page's screen reader has no attribute that takes them.
import WebFoundation

/// The kind of content a text holds, a hint for how assistive technology reads it.
public struct AccessibilityTextContentType: Hashable, Sendable {
    let name: String

    public static var plain: AccessibilityTextContentType { AccessibilityTextContentType(name: "plain") }
    public static var console: AccessibilityTextContentType { AccessibilityTextContentType(name: "console") }
    public static var fileSystem: AccessibilityTextContentType { AccessibilityTextContentType(name: "fileSystem") }
    public static var messaging: AccessibilityTextContentType { AccessibilityTextContentType(name: "messaging") }
    public static var narrative: AccessibilityTextContentType { AccessibilityTextContentType(name: "narrative") }
    public static var sourceCode: AccessibilityTextContentType { AccessibilityTextContentType(name: "sourceCode") }
    public static var spreadsheet: AccessibilityTextContentType { AccessibilityTextContentType(name: "spreadsheet") }
    public static var wordProcessing: AccessibilityTextContentType { AccessibilityTextContentType(name: "wordProcessing") }
}

extension Text {
    /// What assistive technology reads in place of the text.
    public func accessibilityLabel(_ label: Text) -> Text {
        var text = self
        text.accessibilityLabelOverride = label.resolvedString
        return text
    }

    /// What assistive technology reads in place of the text, from a localized key.
    public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> Text { accessibilityLabel(Text(labelKey)) }

    /// What assistive technology reads in place of the text.
    @_disfavoredOverload
    public func accessibilityLabel<S: StringProtocol>(_ label: S) -> Text {
        var text = self
        text.accessibilityLabelOverride = String(label)
        return text
    }

    /// Makes the text a heading of the given level.
    public func accessibilityHeading(_ level: AccessibilityHeadingLevel) -> Text {
        var text = self
        text.accessibilityHeadingLevel = level.level
        return text
    }

    /// Says what kind of content the text holds (kept as a hint only).
    public func accessibilityTextContentType(_ value: AccessibilityTextContentType) -> Text { self }

    /// Raises or lowers the pitch of spoken text (-1 to 1; not spoken differently here).
    public func speechAdjustedPitch(_ value: Double) -> Text { self }
    /// Speaks punctuation (not spoken differently here).
    public func speechAlwaysIncludesPunctuation(_ value: Bool = true) -> Text { self }
    /// Queues an announcement of the text behind the current speech (not spoken differently here).
    public func speechAnnouncementsQueued(_ value: Bool = true) -> Text { self }
    /// Spells the text out letter by letter (not spoken differently here).
    public func speechSpellsOutCharacters(_ value: Bool = true) -> Text { self }
}

extension View {
    /// Says what kind of content the view's text holds (kept as a hint only).
    nonisolated public func accessibilityTextContentType(_ value: AccessibilityTextContentType) -> some View { self }
    /// Raises or lowers the pitch of the view's spoken text (not spoken differently here).
    nonisolated public func speechAdjustedPitch(_ value: Double) -> some View { self }
    /// Speaks the punctuation of the view's text (not spoken differently here).
    nonisolated public func speechAlwaysIncludesPunctuation(_ value: Bool = true) -> some View { self }
    /// Queues announcements of the view's text (not spoken differently here).
    nonisolated public func speechAnnouncementsQueued(_ value: Bool = true) -> some View { self }
    /// Spells the view's text out letter by letter (not spoken differently here).
    nonisolated public func speechSpellsOutCharacters(_ value: Bool = true) -> some View { self }
}
