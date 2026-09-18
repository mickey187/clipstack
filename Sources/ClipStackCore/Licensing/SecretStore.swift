import Foundation

/// The result of trying to read a secret.
///
/// Three cases, not two, and the distinction is the most load-bearing detail in the
/// licensing code. `SecItemCopyMatching` can fail because the item genuinely is not
/// there, *or* because the Keychain is locked, the user cancelled the prompt, or the
/// ACL broke when the app was re-signed.
///
/// Collapsing those into "no record" hands out a fresh trial to anyone who cancels the
/// prompt. Collapsing them into "no licence" locks out someone who has paid. Both are
/// worse than carrying a third case.
public enum SecretReadResult: Equatable, Sendable {
    case found(Data)
    case absent
    case unavailable
}

public protocol SecretStore: Sendable {
    func read(service: String, account: String) -> SecretReadResult
    @discardableResult func write(_ data: Data, service: String, account: String) -> Bool
    @discardableResult func delete(service: String, account: String) -> Bool
}

/// The plain, non-secret side of licensing storage — UserDefaults in the app.
///
/// Deliberately separate from `SecretStore`: nothing here is authoritative. The trial
/// mirror exists only to make a trial *harder to reset*, never to extend one, and the
/// throttle is a performance hint whose loss costs a single extra network call.
public protocol LicenseDefaults: Sendable {
    func loadTrialMirror() -> TrialRecord?
    func saveTrialMirror(_ record: TrialRecord)
    func lastLicenseCheck() -> Date?
    func setLastLicenseCheck(_ date: Date)
}

public enum SecretKeys {
    public static let trialService = "com.mickey.clipstack.trial"
    public static let trialAccount = "trial"
    public static let licenseService = "com.mickey.clipstack.license"
    public static let licenseAccount = "license"
}
