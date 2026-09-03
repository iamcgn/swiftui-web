/// Accessibility modifiers (`Docs/elements/Accessibility.md`): they set attributes on the
/// semantics elements of the modified view, which hosts expose (the canvas host as a DOM
/// overlay with ARIA roles).

/// A set of accessibility traits that describe how an element behaves.
public struct AccessibilityTraits: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 2)
    public static let isLink = AccessibilityTraits(rawValue: 1 << 3)
    public static let isSearchField = AccessibilityTraits(rawValue: 1 << 4)
    public static let isImage = AccessibilityTraits(rawValue: 1 << 5)
    public static let playsSound = AccessibilityTraits(rawValue: 1 << 6)
    public static let isKeyboardKey = AccessibilityTraits(rawValue: 1 << 7)
    public static let isStaticText = AccessibilityTraits(rawValue: 1 << 8)
    public static let isSummaryElement = AccessibilityTraits(rawValue: 1 << 9)
    public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 10)
    public static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 11)
    public static let allowsDirectInteraction = AccessibilityTraits(rawValue: 1 << 12)
    public static let causesPageTurn = AccessibilityTraits(rawValue: 1 << 13)
    public static let isModal = AccessibilityTraits(rawValue: 1 << 14)
    public static let isToggle = AccessibilityTraits(rawValue: 1 << 15)
}

/// Defines the behavior for the child elements of the new accessibility element.
public struct AccessibilityChildBehavior: Hashable, Sendable {
    package enum Kind: Sendable { case contain, combine, ignore }
    package let kind: Kind
    /// Any child accessibility element's properties are ignored.
    public static let ignore = AccessibilityChildBehavior(kind: .ignore)
    /// Any child accessibility elements become children of the new accessibility element.
    public static let contain = AccessibilityChildBehavior(kind: .contain)
    /// Any child accessibility element's properties are merged into the new accessibility element.
    public static let combine = AccessibilityChildBehavior(kind: .combine)
}

/// The attributes an accessibility modifier chain sets on a view's element.
package struct AccessibilityAttributes: Equatable, Sendable {
    package var label: String?
    package var hint: String?
    package var value: String?
    package var identifier: String?
    package var hidden = false
    package var addedTraits: AccessibilityTraits = []
    package var removedTraits: AccessibilityTraits = []
    package var children: AccessibilityChildBehavior?

    package init() {}

    package var isEmpty: Bool { self == AccessibilityAttributes() }

    /// The outer modifier's attributes win over the inner's.
    package func merged(over inner: AccessibilityAttributes) -> AccessibilityAttributes {
        var result = inner
        if let label { result.label = label }
        if let hint { result.hint = hint }
        if let value { result.value = value }
        if let identifier { result.identifier = identifier }
        result.hidden = result.hidden || hidden
        result.addedTraits.formUnion(addedTraits)
        result.removedTraits.formUnion(removedTraits)
        if let children { result.children = children }
        return result
    }
}

public struct _AccessibilityModifier {
    package let attributes: AccessibilityAttributes
    package init(_ attributes: AccessibilityAttributes) { self.attributes = attributes }
}

extension _AccessibilityModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AccessibilityNode(context)
    }
}

extension View {
    private nonisolated func accessibility(_ change: (inout AccessibilityAttributes) -> Void) -> some View {
        var attributes = AccessibilityAttributes()
        change(&attributes)
        return modifier(_AccessibilityModifier(attributes))
    }

    /// Adds a label to the view that describes its contents.
    nonisolated public func accessibilityLabel(_ label: Text) -> some View { accessibility { $0.label = label.resolvedString } }
    nonisolated public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> some View { accessibility { $0.label = Text(labelKey).resolvedString } }
    @_disfavoredOverload
    nonisolated public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View { accessibility { $0.label = String(label) } }

    /// Communicates to the user what happens after performing the view's action.
    nonisolated public func accessibilityHint(_ hint: Text) -> some View { accessibility { $0.hint = hint.resolvedString } }
    nonisolated public func accessibilityHint(_ hintKey: LocalizedStringKey) -> some View { accessibility { $0.hint = Text(hintKey).resolvedString } }
    @_disfavoredOverload
    nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View { accessibility { $0.hint = String(hint) } }

    /// Adds a textual description of the value that the view contains.
    nonisolated public func accessibilityValue(_ value: Text) -> some View { accessibility { $0.value = value.resolvedString } }
    nonisolated public func accessibilityValue(_ valueKey: LocalizedStringKey) -> some View { accessibility { $0.value = Text(valueKey).resolvedString } }
    @_disfavoredOverload
    nonisolated public func accessibilityValue<S: StringProtocol>(_ value: S) -> some View { accessibility { $0.value = String(value) } }

    /// Uses the string you specify to identify the view (tests, automation).
    nonisolated public func accessibilityIdentifier(_ identifier: String) -> some View { accessibility { $0.identifier = identifier } }

    /// Specifies whether to hide this view from system accessibility features.
    nonisolated public func accessibilityHidden(_ hidden: Bool) -> some View { accessibility { $0.hidden = hidden } }

    /// Adds the given traits to the view.
    nonisolated public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View { accessibility { $0.addedTraits = traits } }

    /// Removes the given traits from this view.
    nonisolated public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View { accessibility { $0.removedTraits = traits } }

    /// Creates a new accessibility element, or modifies the existing one, for the view.
    nonisolated public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { accessibility { $0.children = children } }
}
