// The keyboard and content types of text input, shared by SwiftUIWeb (`keyboardType`,
// `textContentType`, `submitLabel`) and UIKitWeb (`UITextField`), so an app importing both sees
// one type. The host maps them to the input element's `inputmode`, `type`, `autocomplete`,
// `autocapitalize` and `enterkeyhint` attributes.

public enum UIKeyboardType: Int, Sendable {
    case `default` = 0, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad

    /// The input element's `inputmode`, nil for the default keyboard.
    public var inputMode: String? {
        switch self {
        case .default, .asciiCapable, .twitter: return nil
        case .numbersAndPunctuation: return "text"
        case .URL: return "url"
        case .numberPad, .asciiCapableNumberPad: return "numeric"
        case .phonePad, .namePhonePad: return "tel"
        case .emailAddress: return "email"
        case .decimalPad: return "decimal"
        case .webSearch: return "search"
        }
    }
}

public enum UIReturnKeyType: Int, Sendable {
    case `default` = 0, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue`

    /// The input element's `enterkeyhint`, nil for the default label.
    public var enterKeyHint: String? {
        switch self {
        case .default, .emergencyCall, .continue: return nil
        case .go, .route: return "go"
        case .google, .search, .yahoo: return "search"
        case .join, .next: return "next"
        case .send: return "send"
        case .done: return "done"
        }
    }
}

public enum UITextAutocapitalizationType: Int, Sendable {
    case none = 0, words, sentences, allCharacters

    /// The input element's `autocapitalize` token.
    public var token: String {
        switch self {
        case .none: return "off"
        case .words: return "words"
        case .sentences: return "sentences"
        case .allCharacters: return "characters"
        }
    }
}

public enum UITextAutocorrectionType: Int, Sendable { case `default` = 0, no, yes }
public enum UITextSpellCheckingType: Int, Sendable { case `default` = 0, no, yes }

/// The semantic kind of a text field's content (`textContentType`): the input element's
/// `autocomplete` token.
public struct UITextContentType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let name = UITextContentType(rawValue: "name")
    public static let namePrefix = UITextContentType(rawValue: "honorific-prefix")
    public static let givenName = UITextContentType(rawValue: "given-name")
    public static let middleName = UITextContentType(rawValue: "additional-name")
    public static let familyName = UITextContentType(rawValue: "family-name")
    public static let nameSuffix = UITextContentType(rawValue: "honorific-suffix")
    public static let nickname = UITextContentType(rawValue: "nickname")
    public static let jobTitle = UITextContentType(rawValue: "organization-title")
    public static let organizationName = UITextContentType(rawValue: "organization")
    public static let location = UITextContentType(rawValue: "street-address")
    public static let fullStreetAddress = UITextContentType(rawValue: "street-address")
    public static let streetAddressLine1 = UITextContentType(rawValue: "address-line1")
    public static let streetAddressLine2 = UITextContentType(rawValue: "address-line2")
    public static let addressCity = UITextContentType(rawValue: "address-level2")
    public static let addressState = UITextContentType(rawValue: "address-level1")
    public static let postalCode = UITextContentType(rawValue: "postal-code")
    public static let countryName = UITextContentType(rawValue: "country-name")
    public static let username = UITextContentType(rawValue: "username")
    public static let password = UITextContentType(rawValue: "current-password")
    public static let newPassword = UITextContentType(rawValue: "new-password")
    public static let oneTimeCode = UITextContentType(rawValue: "one-time-code")
    public static let emailAddress = UITextContentType(rawValue: "email")
    public static let telephoneNumber = UITextContentType(rawValue: "tel")
    public static let creditCardNumber = UITextContentType(rawValue: "cc-number")
    public static let URL = UITextContentType(rawValue: "url")
    public static let birthdate = UITextContentType(rawValue: "bday")
}
