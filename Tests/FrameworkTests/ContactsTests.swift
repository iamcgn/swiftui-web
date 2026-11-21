// Contacts on the web: the store answers as a person who declined access (not granted, a fetch
// or save throws), and the contact values build, label, copy and format as an app writes them
// (OldOS's new-contact sheet, Clendar's permission check).
import Testing
import Contacts
import WebFoundation

@Suite struct ContactsTests {
    final class Answers: @unchecked Sendable { var granted: [Bool] = [] }

    @Test func theStoreDeclinesAndThrows() async throws {
        #expect(CNContactStore.authorizationStatus(for: .contacts) == .denied)
        let store = CNContactStore()
        let answers = Answers()
        store.requestAccess(for: .contacts) { granted, error in answers.granted.append(granted); #expect(error == nil) }
        #expect(answers.granted == [false])
        #expect(try await store.requestAccess(for: .contacts) == false)

        let keys = [CNContactGivenNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        #expect(throws: CNError.self) { try store.containers(matching: nil) }
        #expect(throws: CNError(.authorizationDenied)) {
            try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: "Ada"), keysToFetch: keys)
        }
        #expect(throws: CNError.self) { try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { _, _ in } }

        let request = CNSaveRequest()
        request.add(CNMutableContact(), toContainerWithIdentifier: nil)
        #expect(request.contactsToAdd.count == 1)
        #expect(throws: CNError.self) { try store.execute(request) }
    }

    @Test func aContactIsBuiltLabelledAndCopied() throws {
        let contact = CNMutableContact()
        contact.givenName = "Ada"
        contact.familyName = "Lovelace"
        contact.jobTitle = "Analyst"
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "555-0100"))]
        contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "ada@example.com" as NSString)]
        contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://example.com" as NSString)]
        #expect(contact.phoneNumbers[0].value.stringValue == "555-0100")
        #expect(contact.emailAddresses[0].value as String == "ada@example.com")
        #expect(CNLabeledValue<NSString>.localizedString(forLabel: contact.phoneNumbers[0].label ?? CNLabelOther) == "mobile")
        #expect(CNLabeledValue<NSString>.localizedString(forLabel: CNLabelPhoneNumberiPhone) == "iPhone")
        #expect(CNLabeledValue<NSString>.localizedString(forLabel: "Boat") == "Boat")
        #expect(!contact.imageDataAvailable && contact.isKeyAvailable(CNContactGivenNameKey))

        let relabelled = contact.phoneNumbers[0].settingLabel(CNLabelWork)
        #expect(relabelled.identifier == contact.phoneNumbers[0].identifier && relabelled.label == CNLabelWork)
        #expect(CNPhoneNumber(stringValue: "1") == CNPhoneNumber(stringValue: "1"))

        let frozen = try #require(contact.copy() as? CNContact)
        contact.givenName = "Augusta"
        #expect(frozen.givenName == "Ada" && frozen.identifier == contact.identifier)
        let editable = try #require(frozen.mutableCopy() as? CNMutableContact)
        editable.imageData = Data([1])
        #expect(editable.imageDataAvailable && !frozen.imageDataAvailable)
    }

    @Test func namesAndAddressesFormat() {
        let contact = CNMutableContact()
        #expect(CNContactFormatter.string(from: contact, style: .fullName) == nil)
        contact.namePrefix = "Dr."
        contact.givenName = "Grace"
        contact.familyName = "Hopper"
        #expect(CNContactFormatter.string(from: contact, style: .fullName) == "Dr. Grace Hopper")
        contact.contactType = .organization
        contact.organizationName = "Navy"
        #expect(CNContactFormatter().string(from: contact) == "Navy")

        let address = CNMutablePostalAddress()
        address.street = "1 Main St"
        address.city = "Springfield"
        address.state = "IL"
        address.postalCode = "62701"
        #expect(CNPostalAddressFormatter.string(from: address, style: .mailingAddress) == "1 Main St\nSpringfield, IL 62701")
        #expect(CNContact.localizedString(forKey: CNContactGivenNameKey) == "First name")
    }
}
