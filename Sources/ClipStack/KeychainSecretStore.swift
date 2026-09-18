import ClipStackCore
import Foundation
import Security

/// `SecretStore` backed by the user's login keychain.
///
/// Two deliberate omissions, both of which cost a day of debugging if you get them wrong:
///
/// - **No `kSecUseDataProtectionKeychain`.** That keychain needs an
///   `application-identifier` entitlement, which a Developer ID app without a
///   provisioning profile does not have — every call would fail with
///   `errSecMissingEntitlement`. The legacy file keychain is the right one here, and
///   it is also the one that lives outside the app bundle and so survives the user
///   dragging ClipStack to the Trash. That survival is the entire reason the trial
///   clock lives here rather than in `UserDefaults`.
/// - **No `kSecAttrSynchronizable`.** The trial and the licence are about *this* Mac;
///   syncing them through iCloud Keychain would quietly share an activation.
struct KeychainSecretStore: SecretStore {
    func read(service: String, account: String) -> SecretReadResult {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .unavailable }
            return .found(data)
        case errSecItemNotFound:
            return .absent
        default:
            // Locked keychain, a cancelled prompt, or an ACL broken by re-signing.
            // Emphatically NOT "no record" — see SecretReadResult for why that
            // distinction is load bearing.
            licenseLog.error("keychain read failed for \(service, privacy: .public): OSStatus \(status)")
            return .unavailable
        }
    }

    @discardableResult
    func write(_ data: Data, service: String, account: String) -> Bool {
        let query = baseQuery(service: service, account: account)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }

        guard status == errSecItemNotFound else {
            licenseLog.error("keychain update failed for \(service, privacy: .public): OSStatus \(status)")
            return false
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        insert[kSecAttrLabel as String] = "ClipStack"
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        if addStatus != errSecSuccess {
            licenseLog.error("keychain add failed for \(service, privacy: .public): OSStatus \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    @discardableResult
    func delete(service: String, account: String) -> Bool {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary) == errSecSuccess
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// The non-secret half of licensing storage: a trial mirror that can only ever shorten
/// a trial, and the revalidation throttle.
struct LicenseDefaultsStore: LicenseDefaults {
    private let mirrorKey = "ClipStack.trialMirror"
    private let checkKey = "ClipStack.lastLicenseCheck"

    func loadTrialMirror() -> TrialRecord? {
        guard let data = UserDefaults.standard.data(forKey: mirrorKey) else { return nil }
        return try? JSONDecoder().decode(TrialRecord.self, from: data)
    }

    func saveTrialMirror(_ record: TrialRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: mirrorKey)
    }

    func lastLicenseCheck() -> Date? {
        UserDefaults.standard.object(forKey: checkKey) as? Date
    }

    func setLastLicenseCheck(_ date: Date) {
        UserDefaults.standard.set(date, forKey: checkKey)
    }
}
