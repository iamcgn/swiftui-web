// Keys as hosts deliver them (`KeyEquivalent`, `EventModifiers` and `KeyEvent` in SwiftUI).

/// Key equivalents for keyboard shortcuts and key presses.
public struct KeyEquivalent: Hashable, Sendable {
    public var character: Character

    public init(_ character: Character) { self.character = character }

    public static let upArrow = KeyEquivalent("\u{F700}")
    public static let downArrow = KeyEquivalent("\u{F701}")
    public static let leftArrow = KeyEquivalent("\u{F702}")
    public static let rightArrow = KeyEquivalent("\u{F703}")
    public static let escape = KeyEquivalent("\u{1B}")
    public static let delete = KeyEquivalent("\u{08}")
    public static let deleteForward = KeyEquivalent("\u{7F}")
    public static let `return` = KeyEquivalent("\r")
    public static let space = KeyEquivalent(" ")
    public static let tab = KeyEquivalent("\t")
    public static let home = KeyEquivalent("\u{F729}")
    public static let end = KeyEquivalent("\u{F72B}")
    public static let pageUp = KeyEquivalent("\u{F72C}")
    public static let pageDown = KeyEquivalent("\u{F72D}")
    public static let clear = KeyEquivalent("\u{F739}")

    /// The key equivalent for a DOM `KeyboardEvent.key` value (hosts); nil for modifier and
    /// other keys without an equivalent.
    public init?(domKey: String) {
        switch domKey {
        case "ArrowUp": self = .upArrow
        case "ArrowDown": self = .downArrow
        case "ArrowLeft": self = .leftArrow
        case "ArrowRight": self = .rightArrow
        case "Escape": self = .escape
        case "Backspace": self = .delete
        case "Delete": self = .deleteForward
        case "Enter": self = .return
        case "Tab": self = .tab
        case "Home": self = .home
        case "End": self = .end
        case "PageUp": self = .pageUp
        case "PageDown": self = .pageDown
        case "Clear": self = .clear
        default:
            guard domKey.count == 1, let character = domKey.lowercased().first else { return nil }
            self = KeyEquivalent(character)
        }
    }
}

extension KeyEquivalent: ExpressibleByExtendedGraphemeClusterLiteral {
    public init(extendedGraphemeClusterLiteral value: Character) { self.init(value) }
}

/// A set of key modifiers.
public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let capsLock = EventModifiers(rawValue: 1)
    public static let shift = EventModifiers(rawValue: 2)
    public static let control = EventModifiers(rawValue: 4)
    public static let option = EventModifiers(rawValue: 8)
    public static let command = EventModifiers(rawValue: 16)
    public static let numericPad = EventModifiers(rawValue: 32)
    public static let function = EventModifiers(rawValue: 64)
    public static let all: EventModifiers = [.capsLock, .shift, .control, .option, .command, .numericPad, .function]

    /// The modifiers that distinguish shortcuts (caps lock and the keypad do not).
    public var shortcutModifiers: EventModifiers { intersection([.shift, .control, .option, .command, .function]) }
}

/// A key event as hosts deliver it (`Runtime.keyDown`).
public struct KeyEvent: Sendable {
    public var key: KeyEquivalent
    public var characters: String
    public var modifiers: EventModifiers
    public var isRepeat: Bool

    public init(key: KeyEquivalent, characters: String = "", modifiers: EventModifiers = [], isRepeat: Bool = false) {
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}
