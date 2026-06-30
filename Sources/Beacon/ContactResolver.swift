import Foundation
import Contacts

/// Resolves a Messages handle (phone number or email) to a contact's display
/// name using the system Contacts database.
///
/// Requires Contacts permission (prompted on first use). If it's denied, every
/// lookup returns nil and callers fall back to showing the raw handle.
final class ContactResolver {
    enum State { case idle, loading, ready, denied }

    private(set) var state: State = .idle
    private var phoneMap: [String: String] = [:]  // last 10 digits -> name
    private var emailMap: [String: String] = [:]  // lowercased email -> name

    /// Load contacts once. Requests access the first time; safe to call repeatedly.
    func ensureLoaded() {
        guard state == .idle else { return }
        state = .loading

        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            load(store)
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                guard let self else { return }
                if granted { self.load(store) } else { self.state = .denied }
            }
        default:
            state = .denied
        }
    }

    func name(for handle: String) -> String? {
        guard state == .ready, !handle.isEmpty else { return nil }
        if handle.contains("@") {
            return emailMap[handle.lowercased()]
        }
        let digits = handle.filter { $0.isNumber }
        guard digits.count >= 7 else { return nil }
        return phoneMap[String(digits.suffix(10))]
    }

    private func load(_ store: CNContactStore) {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
            CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var phone: [String: String] = [:]
        var email: [String: String] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = Self.displayName(contact)
                guard !name.isEmpty else { return }
                for number in contact.phoneNumbers {
                    let digits = number.value.stringValue.filter { $0.isNumber }
                    if digits.count >= 7 { phone[String(digits.suffix(10))] = name }
                }
                for address in contact.emailAddresses {
                    email[(address.value as String).lowercased()] = name
                }
            }
            // Publish maps before flipping state so readers see a complete table.
            phoneMap = phone
            emailMap = email
            state = .ready
            Log.write("ContactResolver: loaded phones=\(phone.count) emails=\(email.count)")
        } catch {
            Log.write("ContactResolver: load failed \(error.localizedDescription)")
            state = .denied
        }
    }

    private static func displayName(_ c: CNContact) -> String {
        let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        if !c.nickname.isEmpty { return c.nickname }
        return c.organizationName
    }
}
