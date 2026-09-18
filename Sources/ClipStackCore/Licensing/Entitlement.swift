import Foundation

/// What the app is currently allowed to do. The single source of truth for every
/// licensing decision in the UI — nothing else stores a "is paid" flag.
public enum Entitlement: Equatable, Sendable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed
    /// The server definitively refused the key, but we are inside the grace window.
    /// Still captures: a refund or a Lemon Squeezy mistake should not cost someone
    /// their clipboard mid-sentence.
    case licenseProblem(daysRemaining: Int)
    /// Grace burned. Behaves exactly like an expired trial.
    case licenseRevoked

    /// The one question `ClipboardMonitor` asks.
    public var capturesClipboard: Bool {
        switch self {
        case .trial, .licensed, .licenseProblem: true
        case .trialExpired, .licenseRevoked: false
        }
    }

    public var isPaid: Bool {
        switch self {
        case .licensed, .licenseProblem, .licenseRevoked: true
        case .trial, .trialExpired: false
        }
    }

    /// Shown in the status menu as a non-actionable line. `nil` for a healthy licence —
    /// someone who has paid should not be reminded of it every time they open the menu.
    public var menuTitle: String? {
        switch self {
        case .trial(let days):
            days == 1 ? "1 day left in trial" : "\(days) days left in trial"
        case .trialExpired:
            "Trial ended — new copies aren't being saved"
        case .licensed:
            nil
        case .licenseProblem:
            "There's a problem with your licence"
        case .licenseRevoked:
            "Licence inactive — new copies aren't being saved"
        }
    }

    /// Shown as a banner inside the popup. Deliberately quieter than `menuTitle`:
    /// only surfaces when there is something the user must act on soon.
    public var bannerMessage: String? {
        switch self {
        case .trial(let days) where days <= 3:
            days == 1 ? "Last day of your trial." : "\(days) days left in your trial."
        case .trial:
            nil
        case .trialExpired:
            "Trial ended. New copies aren't being saved."
        case .licensed:
            nil
        case .licenseProblem(let days):
            "We couldn't confirm your licence. \(days) days to sort it out."
        case .licenseRevoked:
            "Licence inactive. New copies aren't being saved."
        }
    }
}

public enum EntitlementPolicy {
    public static let trialLength: TimeInterval = 14 * 86_400
    public static let revalidationInterval: TimeInterval = 30 * 86_400
    public static let revocationGrace: TimeInterval = 7 * 86_400

    /// The whole state machine, as one pure function.
    ///
    /// Order matters. A licence outranks everything, and its age is never consulted:
    /// an offline paying customer is never downgraded, which is the entire point of
    /// the design. A missing trial record means "not started yet", not "expired" —
    /// so an unreadable Keychain fails open.
    public static func evaluate(
        trial: TrialRecord?,
        license: LicenseRecord?,
        now: Date
    ) -> Entitlement {
        if let license {
            guard let refusedAt = license.refusedAt else { return .licensed }
            let left = revocationGrace - now.timeIntervalSince(refusedAt)
            guard left > 0 else { return .licenseRevoked }
            return .licenseProblem(daysRemaining: max(1, Int(ceil(left / 86_400))))
        }

        guard let trial else {
            // No record and no licence: either a first launch, or a Keychain we could
            // not read. Both are treated as a full trial, and neither writes anything.
            return .trial(daysRemaining: Int(trialLength / 86_400))
        }

        if trial.hasExpired(at: now, trialLength: trialLength) {
            return .trialExpired
        }
        return .trial(daysRemaining: trial.daysRemaining(at: now, trialLength: trialLength))
    }
}
