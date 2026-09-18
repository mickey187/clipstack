import Foundation

// Wire types for the Lemon Squeezy License API.
//
// Every field the app does not need is left out on purpose: the server is free to add
// keys, and `JSONDecoder` ignores unknown ones, so additions upstream cannot break
// activation for someone who already paid.

public struct LemonSqueezyMeta: Codable, Equatable, Sendable {
    public let storeID: Int
    public let productID: Int
    public let variantID: Int
    public let customerEmail: String?

    private enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case productID = "product_id"
        case variantID = "variant_id"
        case customerEmail = "customer_email"
    }
}

public struct LemonSqueezyLicenseKey: Codable, Equatable, Sendable {
    public let status: LicenseStatus
    public let key: String
    public let activationLimit: Int?
    public let activationUsage: Int?

    private enum CodingKeys: String, CodingKey {
        case status, key
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
    }
}

public struct LemonSqueezyInstance: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
}

public struct ActivationPayload: Codable, Sendable {
    public let activated: Bool
    public let error: String?
    public let licenseKey: LemonSqueezyLicenseKey?
    public let instance: LemonSqueezyInstance?
    public let meta: LemonSqueezyMeta?

    private enum CodingKeys: String, CodingKey {
        case activated, error, instance, meta
        case licenseKey = "license_key"
    }
}

public struct ValidationPayload: Codable, Sendable {
    public let valid: Bool
    public let error: String?
    public let licenseKey: LemonSqueezyLicenseKey?
    public let instance: LemonSqueezyInstance?
    public let meta: LemonSqueezyMeta?

    private enum CodingKeys: String, CodingKey {
        case valid, error, instance, meta
        case licenseKey = "license_key"
    }
}

/// Why an activation was turned down.
///
/// Every case here is a *definitive* answer from the server. Anything ambiguous —
/// offline, timeout, 500, unparseable body — is `ActivationOutcome.unreachable`
/// instead, because punishing a paying customer for a network blip is the one
/// failure mode this whole design exists to avoid.
public enum ActivationError: Error, Equatable, Sendable {
    case malformedKey
    case notFound
    case limitReached(used: Int, limit: Int)
    case inactive
    case expired
    case disabled
    case wrongProduct
    case notConfigured
    case server(String)

    public var message: String {
        switch self {
        case .malformedKey:
            "That doesn't look like a licence key."
        case .notFound:
            "We couldn't find that licence key. Check it for typos."
        case .limitReached(let used, let limit):
            "This licence is already active on \(used) of \(limit) Macs. Deactivate one first, or write to support."
        case .inactive:
            "That licence isn't active yet."
        case .expired:
            "That licence has expired."
        case .disabled:
            "That licence has been disabled. Write to support if that's unexpected."
        case .wrongProduct:
            "That key is for a different product."
        case .notConfigured:
            "This build isn't configured for purchases yet."
        case .server(let message):
            message
        }
    }
}

public enum ActivationOutcome: Equatable, Sendable {
    case activated(LicenseRecord)
    case refused(ActivationError)
    /// Network, timeout, non-2xx, or a body we could not read. Never punitive.
    case unreachable
}

public enum ValidationOutcome: Equatable, Sendable {
    /// The key and this instance are both good.
    case valid(LicenseStatus)
    /// The server knows the key but no longer recognises this instance — usually
    /// because the user deactivated this Mac from their dashboard.
    case unknownInstance
    /// Definitively bad: refunded, disabled, expired.
    case refused(LicenseStatus)
    case unreachable
}

extension ActivationPayload {
    /// Maps a decoded body onto an outcome, applying the product check.
    ///
    /// Returns `.refused(.wrongProduct)` *with* the instance id so the caller can hand
    /// back the activation slot it just consumed on a stranger's licence.
    func outcome(
        product: ProductIdentity,
        now: Date
    ) -> (outcome: ActivationOutcome, strayInstance: String?) {
        guard activated, let key = licenseKey, let instance, let meta else {
            return (.refused(Self.classify(error: error, status: licenseKey)), nil)
        }
        guard product.matches(meta) else {
            return (.refused(.wrongProduct), instance.id)
        }
        let record = LicenseRecord(
            key: key.key,
            instanceID: instance.id,
            instanceName: instance.name,
            activatedAt: now,
            lastValidatedAt: now,
            status: key.status,
            storeID: meta.storeID,
            productID: meta.productID,
            variantID: meta.variantID,
            customerEmail: meta.customerEmail
        )
        return (.activated(record), nil)
    }

    /// Lemon Squeezy reports refusals as prose, so the message is matched loosely and
    /// always passed through verbatim as a fallback rather than replaced.
    private static func classify(error: String?, status: LemonSqueezyLicenseKey?) -> ActivationError {
        if let status {
            if let limit = status.activationLimit,
               let used = status.activationUsage,
               limit > 0, used >= limit {
                return .limitReached(used: used, limit: limit)
            }
            switch status.status {
            case .expired: return .expired
            case .disabled: return .disabled
            case .inactive: return .inactive
            case .active, .unknown: break
            }
        }
        guard let error, !error.isEmpty else { return .notFound }
        let lowered = error.lowercased()
        if lowered.contains("not found") { return .notFound }
        if lowered.contains("activation limit") { return .limitReached(used: 0, limit: 0) }
        return .server(error)
    }
}
