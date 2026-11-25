// Intents on the web (Docs/support.json, "Intents"): the shortcut, voice shortcut, interaction
// and preference types an app's Siri code names. A page has no Siri: authorization is denied,
// donations are accepted and go nowhere, and the voice shortcuts the user adds through
// IntentsUI's sheets are kept by `INVoiceShortcutCenter` while the page is open, so the app's
// "Add to Siri" flow finishes and its button shows the phrase. Apple's framework re-exports
// Foundation, so a file importing only it names `NSUserActivity` and `UUID`.
@_exported import WebFoundation

// MARK: - Intents and responses

/// A request for the app to do something: Xcode generates its subclasses from an intent
/// definition file.
open class INIntent: NSObject, @unchecked Sendable {
    /// The identifier the system gives the intent once it is donated or run.
    open internal(set) var identifier: String?
    /// The phrase the app suggests the user record for a voice shortcut.
    open var suggestedInvocationPhrase: String?
    /// The intent's description for the shortcut's subtitle.
    open var intentDescription: String?

    public override init() { super.init() }
}

/// The app's answer to an intent.
open class INIntentResponse: NSObject, @unchecked Sendable {
    /// The activity the app continues when the user opens it from the response.
    open var userActivity: NSUserActivity?

    public override init() { super.init() }
}

// MARK: - Shortcuts

/// Something the user can run from Siri or the Shortcuts app: an intent or a user activity.
public enum INShortcut: Hashable, @unchecked Sendable {
    case intent(INIntent)
    case userActivity(NSUserActivity)

    /// A shortcut for the intent (nil for an intent a shortcut can't run; none here).
    public init?(intent: INIntent) { self = .intent(intent) }
    public init(userActivity: NSUserActivity) { self = .userActivity(userActivity) }

    public var intent: INIntent? {
        if case .intent(let intent) = self { return intent }
        return nil
    }

    public var userActivity: NSUserActivity? {
        if case .userActivity(let activity) = self { return activity }
        return nil
    }

    /// The phrase the app suggests for the shortcut: the intent's or the activity's.
    public var _suggestedPhrase: String? {
        switch self {
        case .intent(let intent): intent.suggestedInvocationPhrase
        case .userActivity(let activity): activity.suggestedInvocationPhrase ?? activity.title
        }
    }

    private var _object: ObjectIdentifier {
        switch self {
        case .intent(let intent): ObjectIdentifier(intent)
        case .userActivity(let activity): ObjectIdentifier(activity)
        }
    }

    /// Two shortcuts are equal when they run the same intent or activity object.
    public static func == (lhs: INShortcut, rhs: INShortcut) -> Bool { lhs._object == rhs._object }
    public func hash(into hasher: inout Hasher) { hasher.combine(_object) }
}

#if canImport(Darwin)
import ObjectiveC
#endif

extension NSUserActivity {
    /// The phrase the app suggests the user record for a voice shortcut to the activity.
    public var suggestedInvocationPhrase: String? {
        get { _intentsValue(.phrase) as? String }
        set { _setIntentsValue(newValue, .phrase) }
    }

    /// Whether the activity may be offered as a shortcut (where shortcuts can't be run: kept).
    public var shortcutAvailability: INShortcutAvailabilityOptions {
        get { INShortcutAvailabilityOptions(rawValue: _intentsValue(.availability) as? UInt ?? 0) }
        set { _setIntentsValue(newValue.rawValue, .availability) }
    }
}

enum _IntentsSlot: String { case phrase = "Intents.suggestedInvocationPhrase", availability = "Intents.shortcutAvailability" }

#if canImport(Darwin)
// Apple's Foundation activity has no slot for other frameworks, so the phrase and availability
// ride on it as associated objects (this module stands in for Apple's Intents on a Mac host).
extension NSUserActivity {
    private static func _key(_ slot: _IntentsSlot) -> UnsafeRawPointer {
        switch slot {
        case .phrase: UnsafeRawPointer(bitPattern: 0x1A7E_0001)!
        case .availability: UnsafeRawPointer(bitPattern: 0x1A7E_0002)!
        }
    }

    func _intentsValue(_ slot: _IntentsSlot) -> Any? { objc_getAssociatedObject(self, Self._key(slot)) }
    func _setIntentsValue(_ value: Any?, _ slot: _IntentsSlot) {
        objc_setAssociatedObject(self, Self._key(slot), value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
#else
extension NSUserActivity {
    func _intentsValue(_ slot: _IntentsSlot) -> Any? { _attached[slot.rawValue] }
    func _setIntentsValue(_ value: Any?, _ slot: _IntentsSlot) { _attached[slot.rawValue] = value }
}
#endif

/// The kinds of moment a shortcut suits, for the Shortcuts app's suggestions.
public struct INShortcutAvailabilityOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let sleepMindfulness = INShortcutAvailabilityOptions(rawValue: 1 << 0)
    public static let sleepJournaling = INShortcutAvailabilityOptions(rawValue: 1 << 1)
    public static let sleepMusic = INShortcutAvailabilityOptions(rawValue: 1 << 2)
    public static let sleepPodcasts = INShortcutAvailabilityOptions(rawValue: 1 << 3)
    public static let sleepReading = INShortcutAvailabilityOptions(rawValue: 1 << 4)
    public static let wrapUpYourDay = INShortcutAvailabilityOptions(rawValue: 1 << 5)
    public static let sleepYogaAndStretching = INShortcutAvailabilityOptions(rawValue: 1 << 6)
}

// MARK: - Voice shortcuts

/// A shortcut the user recorded a phrase for.
open class INVoiceShortcut: NSObject, @unchecked Sendable {
    public let identifier: UUID
    public let invocationPhrase: String
    public let shortcut: INShortcut

    init(identifier: UUID = UUID(), invocationPhrase: String, shortcut: INShortcut) {
        self.identifier = identifier
        self.invocationPhrase = invocationPhrase
        self.shortcut = shortcut
        super.init()
    }
}

/// The voice shortcuts the user added for the app: on the web, the ones added through
/// IntentsUI's sheets since the page opened.
public final class INVoiceShortcutCenter: @unchecked Sendable {
    public static let shared = INVoiceShortcutCenter()

    /// The shortcuts the app last suggested to the Shortcuts app.
    public private(set) var _suggestions: [INShortcut] = []
    private var shortcuts: [INVoiceShortcut] = []

    private init() {}

    public func getAllVoiceShortcuts(completion completionHandler: @escaping ([INVoiceShortcut]?, (any Error)?) -> Void) {
        completionHandler(shortcuts, nil)
    }

    public func getVoiceShortcut(with identifier: UUID, completion completionHandler: @escaping (INVoiceShortcut?, (any Error)?) -> Void) {
        completionHandler(shortcuts.first { $0.identifier == identifier }, nil)
    }

    public func allVoiceShortcuts() async throws -> [INVoiceShortcut] { shortcuts }

    public func voiceShortcut(with identifier: UUID) async throws -> INVoiceShortcut? {
        shortcuts.first { $0.identifier == identifier }
    }

    /// Offers the shortcuts to the Shortcuts app (kept: a page has none to show them).
    public func setShortcutSuggestions(_ suggestions: [INShortcut]) { _suggestions = suggestions }

    /// The voice shortcut recorded for the shortcut, if any.
    public func _voiceShortcut(for shortcut: INShortcut) -> INVoiceShortcut? {
        shortcuts.first { $0.shortcut == shortcut }
    }

    /// Records a phrase for the shortcut, replacing one the shortcut had.
    @discardableResult
    public func _add(_ phrase: String, for shortcut: INShortcut) -> INVoiceShortcut {
        let identifier = _voiceShortcut(for: shortcut)?.identifier ?? UUID()
        let added = INVoiceShortcut(identifier: identifier, invocationPhrase: phrase, shortcut: shortcut)
        shortcuts.removeAll { $0.identifier == identifier }
        shortcuts.append(added)
        return added
    }

    public func _remove(_ identifier: UUID) { shortcuts.removeAll { $0.identifier == identifier } }
}

// MARK: - Interactions

/// An intent the app ran, with its response, given to the system so Siri can suggest it again.
open class INInteraction: NSObject, @unchecked Sendable {
    public let intent: INIntent
    public let intentResponse: INIntentResponse?
    open var identifier: String?
    open var groupIdentifier: String?
    open var date = Date()

    public init(intent: INIntent, response: INIntentResponse?) {
        self.intent = intent
        self.intentResponse = response
        super.init()
    }

    /// Gives the interaction to the system: accepted, with nothing to learn from it on a page.
    open func donate(completion: (((any Error)?) -> Void)? = nil) {
        if intent.identifier == nil { intent.identifier = identifier ?? UUID().uuidString }
        completion?(nil)
    }

    open func donate() async throws {}

    open class func delete(with identifiers: [String], completion: (((any Error)?) -> Void)? = nil) { completion?(nil) }
    open class func delete(with groupIdentifier: String, completion: (((any Error)?) -> Void)? = nil) { completion?(nil) }
    open class func deleteAll(completion: (((any Error)?) -> Void)? = nil) { completion?(nil) }
}

// MARK: - Siri authorization

public enum INSiriAuthorizationStatus: Int, Sendable {
    case notDetermined = 0, restricted, denied, authorized
}

/// The user's Siri settings for the app: a page can't use Siri, so access is denied.
open class INPreferences: NSObject, @unchecked Sendable {
    open class func siriAuthorizationStatus() -> INSiriAuthorizationStatus { .denied }

    open class func requestSiriAuthorization(_ handler: @escaping (INSiriAuthorizationStatus) -> Void) {
        handler(.denied)
    }

    /// The language Siri speaks (the page's).
    open class func siriLanguageCode() -> String { Locale.current.identifier.replacingOccurrences(of: "_", with: "-") }
}
