import Foundation
import Contacts

/// Resolves a Messages handle (phone number or email) to a contact's display
/// name using the system Contacts database.
///
/// Requires Contacts permission (prompted on first use). If it's denied, every
/// lookup returns nil and callers fall back to showing the raw handle.
final class ContactResolver {
    enum State { case idle, loading, ready, denied }

    /// Guards state and both maps: `requestAccess`'s completion (and thus
    /// `load`) can run on an arbitrary Contacts-framework thread while
    /// `name(for:)` is called from the engine's message queue.
    private let lock = NSLock()
    private var _state: State = .idle
    private var phoneMap: [String: String] = [:]  // last 10 digits -> name
    private var emailMap: [String: String] = [:]  // lowercased email -> name

    var state: State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    /// True once contacts are fully loaded, so lookups are complete and stable
    /// (callers may cache the results).
    var isReady: Bool { state == .ready }

    /// Load contacts once. Requests access the first time; safe to call
    /// repeatedly. A previously denied resolver re-checks authorization, so
    /// granting access in System Settings works without a relaunch.
    func ensureLoaded() {
        lock.lock()
        switch _state {
        case .idle:
            _state = .loading
        case .denied where CNContactStore.authorizationStatus(for: .contacts) == .authorized:
            _state = .loading
        default:
            lock.unlock()
            return
        }
        lock.unlock()

        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            load(store)
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                guard let self else { return }
                if granted { self.load(store) } else { self.setState(.denied) }
            }
        default:
            setState(.denied)
        }
    }

    func name(for handle: String) -> String? {
        guard !handle.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard _state == .ready else { return nil }
        if handle.contains("@") {
            return emailMap[handle.lowercased()]
        }
        let digits = handle.filter { $0.isNumber }
        guard digits.count >= 7 else { return nil }
        return phoneMap[String(digits.suffix(10))]
    }

    private func setState(_ newState: State) {
        lock.lock()
        _state = newState
        lock.unlock()
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
            // Publish maps and state together so readers see a complete table.
            lock.lock()
            phoneMap = phone
            emailMap = email
            _state = .ready
            lock.unlock()
            Log.write("ContactResolver: loaded phones=\(phone.count) emails=\(email.count)")
        } catch {
            Log.write("ContactResolver: load failed \(error.localizedDescription)")
            setState(.denied)
        }
    }

    private static func displayName(_ c: CNContact) -> String {
        let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        if !c.nickname.isEmpty { return c.nickname }
        return c.organizationName
    }
}
