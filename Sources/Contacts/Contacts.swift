// Contacts on the web: a page cannot reach the person's address book, so the store answers every
// access request as a person who declined it would (not granted, no error), reports the access as
// denied, and throws `authorizationDenied` from its fetches and saves, as a device does for an app
// without access. The contact types are values an app fills and reads, so the code that builds a
// contact, labels its numbers and formats its name compiles and runs (OldOS, Clendar).
// Apple's frameworks re-export Foundation: a file importing only this module names Data.
@_exported import WebFoundation
#if os(WASI)
import WebCoreData   // NSPredicate, which Apple's Foundation declares
#endif

/// The kinds of entity a contact store holds.
public enum CNEntityType: Int, Sendable {
    case contacts = 0
}

/// Whether the app may reach the person's contacts.
public enum CNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3
    case limited = 4
}

/// A person or an organization.
public enum CNContactType: Int, Sendable {
    case person = 0
    case organization = 1
}

/// The order contacts are sorted in.
public enum CNContactSortOrder: Int, Sendable {
    case none = 0, userDefault, givenName, familyName
}

/// Where a store keeps its contacts.
public enum CNContainerType: Int, Sendable {
    case unassigned = 0, local, exchange, cardDAV
}

/// The errors a contact store throws.
public struct CNError: Error, Sendable, Equatable {
    public enum Code: Int, Sendable {
        case communicationError = 1
        case dataAccessError = 2
        case authorizationDenied = 100
        case noAccessableWritableContainers = 101
        case unauthorizedKeys = 102
        case featureDisabledByUser = 103
        case recordDoesNotExist = 200
        case insertedRecordAlreadyExists = 201
        case recordIdentifierInvalid = 205
        case validationMultipleErrors = 300
        case validationTypeMismatch = 301
        case predicateInvalid = 400
        case policyViolation = 500
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public static var authorizationDenied: Code { .authorizationDenied }
    public static var recordDoesNotExist: Code { .recordDoesNotExist }
    public static var dataAccessError: Code { .dataAccessError }
}

/// The domain of the contact store's errors.
public let CNErrorDomain = "CNErrorDomain"

/// A key a fetch asks for: a contact key (`CNContactGivenNameKey as CNKeyDescriptor`) or the
/// descriptor a formatter gives.
public protocol CNKeyDescriptor {}
extension String: CNKeyDescriptor {}

// MARK: - Keys and labels

public let CNContactIdentifierKey = "identifier"
public let CNContactNamePrefixKey = "namePrefix"
public let CNContactGivenNameKey = "givenName"
public let CNContactMiddleNameKey = "middleName"
public let CNContactFamilyNameKey = "familyName"
public let CNContactPreviousFamilyNameKey = "previousFamilyName"
public let CNContactNameSuffixKey = "nameSuffix"
public let CNContactNicknameKey = "nickname"
public let CNContactOrganizationNameKey = "organizationName"
public let CNContactDepartmentNameKey = "departmentName"
public let CNContactJobTitleKey = "jobTitle"
public let CNContactPhoneticGivenNameKey = "phoneticGivenName"
public let CNContactPhoneticMiddleNameKey = "phoneticMiddleName"
public let CNContactPhoneticFamilyNameKey = "phoneticFamilyName"
public let CNContactPhoneticOrganizationNameKey = "phoneticOrganizationName"
public let CNContactNoteKey = "note"
public let CNContactTypeKey = "contactType"
public let CNContactImageDataKey = "imageData"
public let CNContactBirthdayKey = "birthday"
public let CNContactNonGregorianBirthdayKey = "nonGregorianBirthday"
public let CNContactPhoneNumbersKey = "phoneNumbers"
public let CNContactEmailAddressesKey = "emailAddresses"
public let CNContactPostalAddressesKey = "postalAddresses"
public let CNContactUrlAddressesKey = "urlAddresses"
public let CNContactRelationsKey = "contactRelations"
public let CNContactSocialProfilesKey = "socialProfiles"
public let CNContactInstantMessageAddressesKey = "instantMessageAddresses"
public let CNContactImageDataAvailableKey = "imageDataAvailable"
public let CNContactThumbnailImageDataKey = "thumbnailImageData"
public let CNContactDatesKey = "dates"
public let CNPostalAddressStreetKey = "street"
public let CNPostalAddressSubLocalityKey = "subLocality"
public let CNPostalAddressCityKey = "city"
public let CNPostalAddressSubAdministrativeAreaKey = "subAdministrativeArea"
public let CNPostalAddressStateKey = "state"
public let CNPostalAddressPostalCodeKey = "postalCode"
public let CNPostalAddressCountryKey = "country"
public let CNPostalAddressISOCountryCodeKey = "isoCountryCode"

public let CNLabelHome = "_$!<Home>!$_"
public let CNLabelWork = "_$!<Work>!$_"
public let CNLabelSchool = "_$!<School>!$_"
public let CNLabelOther = "_$!<Other>!$_"
public let CNLabelURLAddressHomePage = "_$!<HomePage>!$_"
public let CNLabelDateAnniversary = "_$!<Anniversary>!$_"
public let CNLabelPhoneNumberMobile = "_$!<Mobile>!$_"
public let CNLabelPhoneNumberMain = "_$!<Main>!$_"
public let CNLabelPhoneNumberHomeFax = "_$!<HomeFAX>!$_"
public let CNLabelPhoneNumberWorkFax = "_$!<WorkFAX>!$_"
public let CNLabelPhoneNumberOtherFax = "_$!<OtherFAX>!$_"
public let CNLabelPhoneNumberPager = "_$!<Pager>!$_"
public let CNLabelPhoneNumberAppleWatch = "_$!<AppleWatch>!$_"
public let CNLabelContactRelationFather = "_$!<Father>!$_"
public let CNLabelContactRelationMother = "_$!<Mother>!$_"
public let CNLabelContactRelationParent = "_$!<Parent>!$_"
public let CNLabelContactRelationBrother = "_$!<Brother>!$_"
public let CNLabelContactRelationSister = "_$!<Sister>!$_"
public let CNLabelContactRelationChild = "_$!<Child>!$_"
public let CNLabelContactRelationFriend = "_$!<Friend>!$_"
public let CNLabelContactRelationSpouse = "_$!<Spouse>!$_"
public let CNLabelContactRelationPartner = "_$!<Partner>!$_"
public let CNLabelContactRelationAssistant = "_$!<Assistant>!$_"
public let CNLabelContactRelationManager = "_$!<Manager>!$_"
public let CNLabelPhoneNumberiPhone = "iPhone"
public let CNLabelEmailiCloud = "iCloud"

private let localizedLabels: [String: String] = [
        CNLabelHome: "home",
        CNLabelWork: "work",
        CNLabelSchool: "school",
        CNLabelOther: "other",
        CNLabelURLAddressHomePage: "homepage",
        CNLabelDateAnniversary: "anniversary",
        CNLabelPhoneNumberMobile: "mobile",
        CNLabelPhoneNumberMain: "main",
        CNLabelPhoneNumberHomeFax: "home fax",
        CNLabelPhoneNumberWorkFax: "work fax",
        CNLabelPhoneNumberOtherFax: "other fax",
        CNLabelPhoneNumberPager: "pager",
        CNLabelPhoneNumberAppleWatch: "Apple Watch",
        CNLabelContactRelationFather: "father",
        CNLabelContactRelationMother: "mother",
        CNLabelContactRelationParent: "parent",
        CNLabelContactRelationBrother: "brother",
        CNLabelContactRelationSister: "sister",
        CNLabelContactRelationChild: "child",
        CNLabelContactRelationFriend: "friend",
        CNLabelContactRelationSpouse: "spouse",
        CNLabelContactRelationPartner: "partner",
        CNLabelContactRelationAssistant: "assistant",
        CNLabelContactRelationManager: "manager",
        CNLabelPhoneNumberiPhone: "iPhone",
        CNLabelEmailiCloud: "iCloud"
]

// MARK: - Values

/// The fields of a contact, shared by the contact and its mutable form.
struct _CNContactFields {
    var identifier = UUID().uuidString
    var namePrefix: String = ""
    var givenName: String = ""
    var middleName: String = ""
    var familyName: String = ""
    var previousFamilyName: String = ""
    var nameSuffix: String = ""
    var nickname: String = ""
    var organizationName: String = ""
    var departmentName: String = ""
    var jobTitle: String = ""
    var phoneticGivenName: String = ""
    var phoneticMiddleName: String = ""
    var phoneticFamilyName: String = ""
    var phoneticOrganizationName: String = ""
    var note: String = ""
    var contactType: CNContactType = .person
    var imageData: Data? = nil
    var birthday: DateComponents? = nil
    var nonGregorianBirthday: DateComponents? = nil
    var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] = []
    var emailAddresses: [CNLabeledValue<NSString>] = []
    var postalAddresses: [CNLabeledValue<CNPostalAddress>] = []
    var urlAddresses: [CNLabeledValue<NSString>] = []
    var contactRelations: [CNLabeledValue<CNContactRelation>] = []
    var socialProfiles: [CNLabeledValue<CNSocialProfile>] = []
    var instantMessageAddresses: [CNLabeledValue<CNInstantMessageAddress>] = []
}

/// A contact: read-only; `CNMutableContact` (or `mutableCopy()`) changes one.
open class CNContact: NSObject, NSCopying, NSMutableCopying, @unchecked Sendable {
    var _fields: _CNContactFields

    public override init() {
        _fields = _CNContactFields()
        super.init()
    }
    init(_ fields: _CNContactFields) {
        _fields = fields
        super.init()
    }

    public var identifier: String { _fields.identifier }
    public var namePrefix: String { _fields.namePrefix }
    public var givenName: String { _fields.givenName }
    public var middleName: String { _fields.middleName }
    public var familyName: String { _fields.familyName }
    public var previousFamilyName: String { _fields.previousFamilyName }
    public var nameSuffix: String { _fields.nameSuffix }
    public var nickname: String { _fields.nickname }
    public var organizationName: String { _fields.organizationName }
    public var departmentName: String { _fields.departmentName }
    public var jobTitle: String { _fields.jobTitle }
    public var phoneticGivenName: String { _fields.phoneticGivenName }
    public var phoneticMiddleName: String { _fields.phoneticMiddleName }
    public var phoneticFamilyName: String { _fields.phoneticFamilyName }
    public var phoneticOrganizationName: String { _fields.phoneticOrganizationName }
    public var note: String { _fields.note }
    public var contactType: CNContactType { _fields.contactType }
    public var imageData: Data? { _fields.imageData }
    public var birthday: DateComponents? { _fields.birthday }
    public var nonGregorianBirthday: DateComponents? { _fields.nonGregorianBirthday }
    public var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] { _fields.phoneNumbers }
    public var emailAddresses: [CNLabeledValue<NSString>] { _fields.emailAddresses }
    public var postalAddresses: [CNLabeledValue<CNPostalAddress>] { _fields.postalAddresses }
    public var urlAddresses: [CNLabeledValue<NSString>] { _fields.urlAddresses }
    public var contactRelations: [CNLabeledValue<CNContactRelation>] { _fields.contactRelations }
    public var socialProfiles: [CNLabeledValue<CNSocialProfile>] { _fields.socialProfiles }
    public var instantMessageAddresses: [CNLabeledValue<CNInstantMessageAddress>] { _fields.instantMessageAddresses }
    public var thumbnailImageData: Data? { _fields.imageData }
    public var imageDataAvailable: Bool { _fields.imageData != nil }

    /// Whether a fetch asked for the key: every key is here.
    public func isKeyAvailable(_ key: String) -> Bool { true }
    /// Whether a fetch asked for the keys: every key is here.
    public func areKeysAvailable(_ keyDescriptors: [any CNKeyDescriptor]) -> Bool { true }

    #if canImport(ObjectiveC)
    @objc open func copy(with zone: NSZone? = nil) -> Any { CNContact(_fields) }
    @objc open func mutableCopy(with zone: NSZone? = nil) -> Any { CNMutableContact(_fields) }
    #else
    open func copy(with zone: NSZone? = nil) -> Any { CNContact(_fields) }
    open func mutableCopy(with zone: NSZone? = nil) -> Any { CNMutableContact(_fields) }
    #endif

    /// The name a key's property shows under, as the Contacts app labels it.
    public class func localizedString(forKey key: String) -> String {
        switch key {
        case CNContactGivenNameKey: "First name"
        case CNContactFamilyNameKey: "Last name"
        case CNContactMiddleNameKey: "Middle name"
        case CNContactNicknameKey: "Nickname"
        case CNContactOrganizationNameKey: "Company"
        case CNContactJobTitleKey: "Job title"
        case CNContactPhoneNumbersKey: "Phone"
        case CNContactEmailAddressesKey: "Email"
        case CNContactPostalAddressesKey: "Address"
        case CNContactUrlAddressesKey: "URL"
        case CNContactBirthdayKey: "Birthday"
        case CNContactNoteKey: "Notes"
        default: key
        }
    }

    /// The keys a sort by name needs.
    public class func descriptorForAllComparatorKeys() -> any CNKeyDescriptor { CNContactFamilyNameKey }

    // Queries for a store's fetch. The store holds nothing a page can reach, so each matches nothing.
    public class func predicateForContacts(matchingName name: String) -> NSPredicate { NSPredicate(value: false) }
    public class func predicateForContacts(withIdentifiers identifiers: [String]) -> NSPredicate { NSPredicate(value: false) }
    public class func predicateForContacts(matchingEmailAddress emailAddress: String) -> NSPredicate { NSPredicate(value: false) }
    public class func predicateForContacts(matching phoneNumber: CNPhoneNumber) -> NSPredicate { NSPredicate(value: false) }
    public class func predicateForContactsInContainer(withIdentifier containerIdentifier: String) -> NSPredicate { NSPredicate(value: false) }
    public class func predicateForContactsInGroup(withIdentifier groupIdentifier: String) -> NSPredicate { NSPredicate(value: false) }
}

/// A contact an app fills in.
open class CNMutableContact: CNContact, @unchecked Sendable {
    public override var namePrefix: String { get { _fields.namePrefix } set { _fields.namePrefix = newValue } }
    public override var givenName: String { get { _fields.givenName } set { _fields.givenName = newValue } }
    public override var middleName: String { get { _fields.middleName } set { _fields.middleName = newValue } }
    public override var familyName: String { get { _fields.familyName } set { _fields.familyName = newValue } }
    public override var previousFamilyName: String { get { _fields.previousFamilyName } set { _fields.previousFamilyName = newValue } }
    public override var nameSuffix: String { get { _fields.nameSuffix } set { _fields.nameSuffix = newValue } }
    public override var nickname: String { get { _fields.nickname } set { _fields.nickname = newValue } }
    public override var organizationName: String { get { _fields.organizationName } set { _fields.organizationName = newValue } }
    public override var departmentName: String { get { _fields.departmentName } set { _fields.departmentName = newValue } }
    public override var jobTitle: String { get { _fields.jobTitle } set { _fields.jobTitle = newValue } }
    public override var phoneticGivenName: String { get { _fields.phoneticGivenName } set { _fields.phoneticGivenName = newValue } }
    public override var phoneticMiddleName: String { get { _fields.phoneticMiddleName } set { _fields.phoneticMiddleName = newValue } }
    public override var phoneticFamilyName: String { get { _fields.phoneticFamilyName } set { _fields.phoneticFamilyName = newValue } }
    public override var phoneticOrganizationName: String { get { _fields.phoneticOrganizationName } set { _fields.phoneticOrganizationName = newValue } }
    public override var note: String { get { _fields.note } set { _fields.note = newValue } }
    public override var contactType: CNContactType { get { _fields.contactType } set { _fields.contactType = newValue } }
    public override var imageData: Data? { get { _fields.imageData } set { _fields.imageData = newValue } }
    public override var birthday: DateComponents? { get { _fields.birthday } set { _fields.birthday = newValue } }
    public override var nonGregorianBirthday: DateComponents? { get { _fields.nonGregorianBirthday } set { _fields.nonGregorianBirthday = newValue } }
    public override var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] { get { _fields.phoneNumbers } set { _fields.phoneNumbers = newValue } }
    public override var emailAddresses: [CNLabeledValue<NSString>] { get { _fields.emailAddresses } set { _fields.emailAddresses = newValue } }
    public override var postalAddresses: [CNLabeledValue<CNPostalAddress>] { get { _fields.postalAddresses } set { _fields.postalAddresses = newValue } }
    public override var urlAddresses: [CNLabeledValue<NSString>] { get { _fields.urlAddresses } set { _fields.urlAddresses = newValue } }
    public override var contactRelations: [CNLabeledValue<CNContactRelation>] { get { _fields.contactRelations } set { _fields.contactRelations = newValue } }
    public override var socialProfiles: [CNLabeledValue<CNSocialProfile>] { get { _fields.socialProfiles } set { _fields.socialProfiles = newValue } }
    public override var instantMessageAddresses: [CNLabeledValue<CNInstantMessageAddress>] { get { _fields.instantMessageAddresses } set { _fields.instantMessageAddresses = newValue } }
}

/// A value with a label: a phone number, an address or a relation, tagged home, work, mobile.
public final class CNLabeledValue<ValueType>: NSObject, @unchecked Sendable {
    public let identifier: String
    public let label: String?
    public let value: ValueType

    public init(label: String?, value: ValueType) {
        identifier = UUID().uuidString
        self.label = label
        self.value = value
        super.init()
    }
    private init(identifier: String, label: String?, value: ValueType) {
        self.identifier = identifier
        self.label = label
        self.value = value
        super.init()
    }

    public func settingLabel(_ label: String?) -> CNLabeledValue<ValueType> { CNLabeledValue(identifier: identifier, label: label, value: value) }
    public func settingValue(_ value: ValueType) -> CNLabeledValue<ValueType> { CNLabeledValue(identifier: identifier, label: label, value: value) }
    public func settingLabel(_ label: String?, value: ValueType) -> CNLabeledValue<ValueType> { CNLabeledValue(identifier: identifier, label: label, value: value) }

    /// The label as the Contacts app shows it ("home", "mobile"); a label of the app's own as is.
    public class func localizedString(forLabel label: String) -> String { localizedLabels[label] ?? label }
}

/// A phone number, as the person typed it.
public final class CNPhoneNumber: NSObject, NSCopying, @unchecked Sendable {
    public let stringValue: String
    public init(stringValue: String) {
        self.stringValue = stringValue
        super.init()
    }
    public convenience override init() { self.init(stringValue: "") }
    public class func phoneNumber(withStringValue stringValue: String) -> CNPhoneNumber { CNPhoneNumber(stringValue: stringValue) }
    public override func isEqual(_ object: Any?) -> Bool { (object as? CNPhoneNumber)?.stringValue == stringValue }
    public override var hash: Int { stringValue.hashValue }
    #if canImport(ObjectiveC)
    @objc public func copy(with zone: NSZone? = nil) -> Any { self }
    #else
    public func copy(with zone: NSZone? = nil) -> Any { self }
    #endif
}

struct _CNPostalAddressFields {
    var street = ""
    var subLocality = ""
    var city = ""
    var subAdministrativeArea = ""
    var state = ""
    var postalCode = ""
    var country = ""
    var isoCountryCode = ""
}

/// A postal address: read-only; `CNMutablePostalAddress` fills one.
open class CNPostalAddress: NSObject, NSCopying, NSMutableCopying, @unchecked Sendable {
    var _fields: _CNPostalAddressFields
    public override init() {
        _fields = _CNPostalAddressFields()
        super.init()
    }
    init(_ fields: _CNPostalAddressFields) {
        _fields = fields
        super.init()
    }
    public var street: String { _fields.street }
    public var subLocality: String { _fields.subLocality }
    public var city: String { _fields.city }
    public var subAdministrativeArea: String { _fields.subAdministrativeArea }
    public var state: String { _fields.state }
    public var postalCode: String { _fields.postalCode }
    public var country: String { _fields.country }
    public var isoCountryCode: String { _fields.isoCountryCode }
    #if canImport(ObjectiveC)
    @objc open func copy(with zone: NSZone? = nil) -> Any { CNPostalAddress(_fields) }
    @objc open func mutableCopy(with zone: NSZone? = nil) -> Any { CNMutablePostalAddress(_fields) }
    #else
    open func copy(with zone: NSZone? = nil) -> Any { CNPostalAddress(_fields) }
    open func mutableCopy(with zone: NSZone? = nil) -> Any { CNMutablePostalAddress(_fields) }
    #endif

    /// The name a key's field shows under.
    public class func localizedString(forKey key: String) -> String {
        switch key {
        case CNPostalAddressStreetKey: "Street"
        case CNPostalAddressCityKey: "City"
        case CNPostalAddressStateKey: "State"
        case CNPostalAddressPostalCodeKey: "ZIP"
        case CNPostalAddressCountryKey: "Country"
        default: key
        }
    }
}

/// A postal address an app fills in.
open class CNMutablePostalAddress: CNPostalAddress, @unchecked Sendable {
    public override var street: String { get { _fields.street } set { _fields.street = newValue } }
    public override var subLocality: String { get { _fields.subLocality } set { _fields.subLocality = newValue } }
    public override var city: String { get { _fields.city } set { _fields.city = newValue } }
    public override var subAdministrativeArea: String { get { _fields.subAdministrativeArea } set { _fields.subAdministrativeArea = newValue } }
    public override var state: String { get { _fields.state } set { _fields.state = newValue } }
    public override var postalCode: String { get { _fields.postalCode } set { _fields.postalCode = newValue } }
    public override var country: String { get { _fields.country } set { _fields.country = newValue } }
    public override var isoCountryCode: String { get { _fields.isoCountryCode } set { _fields.isoCountryCode = newValue } }
}

/// How a postal address formatter lays an address out.
public enum CNPostalAddressFormatterStyle: Int, Sendable {
    case mailingAddress = 0
}

/// Lays a postal address out as a letter's envelope would: street, then city, state and postal
/// code, then country.
open class CNPostalAddressFormatter: NSObject, @unchecked Sendable {
    open var style: CNPostalAddressFormatterStyle = .mailingAddress
    public class func string(from postalAddress: CNPostalAddress, style: CNPostalAddressFormatterStyle) -> String {
        let locality = [postalAddress.city, [postalAddress.state, postalAddress.postalCode].filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        return [postalAddress.street, locality, postalAddress.country].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    open func string(from postalAddress: CNPostalAddress) -> String { Self.string(from: postalAddress, style: style) }
}

/// A related person: a name, labelled with how they're related.
public final class CNContactRelation: NSObject, @unchecked Sendable {
    public let name: String
    public init(name: String) {
        self.name = name
        super.init()
    }
}

/// An account on a social service.
public final class CNSocialProfile: NSObject, @unchecked Sendable {
    public let urlString: String
    public let username: String
    public let userIdentifier: String
    public let service: String
    public init(urlString: String?, username: String?, userIdentifier: String?, service: String?) {
        self.urlString = urlString ?? ""
        self.username = username ?? ""
        self.userIdentifier = userIdentifier ?? ""
        self.service = service ?? ""
        super.init()
    }
}

/// An address on a messaging service.
public final class CNInstantMessageAddress: NSObject, @unchecked Sendable {
    public let username: String
    public let service: String
    public init(username: String, service: String) {
        self.username = username
        self.service = service
        super.init()
    }
}

// MARK: - Formatting

/// How a contact formatter writes a name.
public enum CNContactFormatterStyle: Int, Sendable {
    case fullName = 0
    case phoneticFullName = 1
}

/// Which name comes first when a name is written out.
public enum CNContactDisplayNameOrder: Int, Sendable {
    case userDefault = 0, givenNameFirst, familyNameFirst
}

/// Writes a contact's name: prefix, given, middle and family names and suffix, given name first;
/// an organization's name for an organization.
open class CNContactFormatter: NSObject, @unchecked Sendable {
    open var style: CNContactFormatterStyle = .fullName

    public class func string(from contact: CNContact, style: CNContactFormatterStyle) -> String? {
        let parts: [String]
        switch style {
        case .fullName:
            if contact.contactType == .organization { return contact.organizationName.isEmpty ? nil : contact.organizationName }
            parts = [contact.namePrefix, contact.givenName, contact.middleName, contact.familyName, contact.nameSuffix]
        case .phoneticFullName:
            parts = [contact.phoneticGivenName, contact.phoneticMiddleName, contact.phoneticFamilyName]
        }
        let name = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }
    open func string(from contact: CNContact) -> String? { Self.string(from: contact, style: style) }
    public class func nameOrder(for contact: CNContact) -> CNContactDisplayNameOrder { .givenNameFirst }
    public class func delimiter(for contact: CNContact) -> String { " " }
    /// The keys a formatter reads to write a name.
    public class func descriptorForRequiredKeys(for style: CNContactFormatterStyle) -> any CNKeyDescriptor { CNContactGivenNameKey }
}

// MARK: - The store

/// A place a store keeps contacts.
public final class CNContainer: NSObject, @unchecked Sendable {
    public let identifier: String
    public let name: String
    public let type: CNContainerType
    init(identifier: String, name: String, type: CNContainerType) {
        self.identifier = identifier
        self.name = name
        self.type = type
        super.init()
    }
    public class func predicateForContainers(withIdentifiers identifiers: [String]) -> NSPredicate { NSPredicate(value: false) }
}

/// A group of contacts.
open class CNGroup: NSObject, @unchecked Sendable {
    var _name = ""
    public let identifier = UUID().uuidString
    public var name: String { _name }
    public class func predicateForGroups(withIdentifiers identifiers: [String]) -> NSPredicate { NSPredicate(value: false) }
}

/// A group an app fills in.
open class CNMutableGroup: CNGroup, @unchecked Sendable {
    public override var name: String { get { _name } set { _name = newValue } }
}

/// A fetch: the keys to read, and which contacts and in what order.
open class CNContactFetchRequest: NSObject, @unchecked Sendable {
    open var keysToFetch: [any CNKeyDescriptor]
    open var predicate: NSPredicate?
    open var mutableObjects = false
    open var unifyResults = true
    open var sortOrder: CNContactSortOrder = .none
    public init(keysToFetch: [any CNKeyDescriptor]) {
        self.keysToFetch = keysToFetch
        super.init()
    }
}

/// The changes a store's `execute(_:)` makes together.
open class CNSaveRequest: NSObject, @unchecked Sendable {
    public private(set) var contactsToAdd: [CNMutableContact] = []
    public private(set) var contactsToUpdate: [CNMutableContact] = []
    public private(set) var contactsToDelete: [CNMutableContact] = []
    open var transactionAuthor: String?
    open func add(_ contact: CNMutableContact, toContainerWithIdentifier identifier: String?) { contactsToAdd.append(contact) }
    open func update(_ contact: CNMutableContact) { contactsToUpdate.append(contact) }
    open func delete(_ contact: CNMutableContact) { contactsToDelete.append(contact) }
    open func add(_ group: CNMutableGroup, toContainerWithIdentifier identifier: String?) {}
    open func update(_ group: CNMutableGroup) {}
    open func delete(_ group: CNMutableGroup) {}
    open func addMember(_ contact: CNContact, to group: CNGroup) {}
    open func removeMember(_ contact: CNContact, from group: CNGroup) {}
}

/// The person's contacts, out of a page's reach: access is declined and every fetch or save
/// throws `authorizationDenied`, as for an app the person has not let in.
open class CNContactStore: NSObject, @unchecked Sendable {
    public override init() { super.init() }

    /// The app's access: denied.
    public class func authorizationStatus(for entityType: CNEntityType) -> CNAuthorizationStatus { .denied }
    /// Asks for access: not granted.
    open func requestAccess(for entityType: CNEntityType, completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        completionHandler(false, nil)
    }
    open func requestAccess(for entityType: CNEntityType) async throws -> Bool { false }

    open func unifiedContacts(matching predicate: NSPredicate, keysToFetch keys: [any CNKeyDescriptor]) throws -> [CNContact] {
        throw CNError(.authorizationDenied)
    }
    open func unifiedContact(withIdentifier identifier: String, keysToFetch keys: [any CNKeyDescriptor]) throws -> CNContact {
        throw CNError(.authorizationDenied)
    }
    open func unifiedMeContactWithKeys(toFetch keys: [any CNKeyDescriptor]) throws -> CNContact { throw CNError(.authorizationDenied) }
    open func enumerateContacts(with fetchRequest: CNContactFetchRequest, usingBlock block: (CNContact, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        throw CNError(.authorizationDenied)
    }
    open func groups(matching predicate: NSPredicate?) throws -> [CNGroup] { throw CNError(.authorizationDenied) }
    open func containers(matching predicate: NSPredicate?) throws -> [CNContainer] { throw CNError(.authorizationDenied) }
    open func defaultContainerIdentifier() -> String { "" }
    open func execute(_ saveRequest: CNSaveRequest) throws { throw CNError(.authorizationDenied) }
    open var currentHistoryToken: Data? { nil }
}

extension Notification.Name {
    /// Posted when the store's contacts change: never, as a page holds none.
    public static let CNContactStoreDidChange = Notification.Name("CNContactStoreDidChangeNotification")
}
