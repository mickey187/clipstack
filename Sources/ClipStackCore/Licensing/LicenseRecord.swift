import Foundation

/// What Lemon Squeezy says a key is, mapped so an unrecognised value can never
/// throw a decode error and lock someone out.
public enum LicenseStatus: String, Codable, Equatable, Sendable {
    case active, inactive, expired, disabled
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LicenseStatus(rawValue: raw) ?? .unknown
    }

    /// Statuses that mean "this key is no good", as opposed to merely unrecognised.
    /// `.unknown` is deliberately absent: a status we cannot parse is not a refusal.
    public var isDefinitivelyBad: Bool {
        self == .expired || self == .disabled
    }
}

/// A successful activation, as written to the Keychain.
public struct LicenseRecord: Codable, Equatable, Sendable {
    public private(set) var schema: Int
    public let key: String
    public let instanceID: String
    public let instanceName: String
    public let activatedAt: Date
    public var lastValidatedAt: Date
    /// Set the first time the server definitively refuses this key. Starts the grace
    /// window; cleared by any later success.
    public var refusedAt: Date?
    public var status: LicenseStatus
    public let storeID: Int
    public let productID: Int
    public let variantID: Int
    public let customerEmail: String?

    public static let currentSchema = 1

    public init(
        key: String,
        instanceID: String,
        instanceName: String,
        activatedAt: Date,
        lastValidatedAt: Date,
        refusedAt: Date? = nil,
        status: LicenseStatus,
        storeID: Int,
        productID: Int,
        variantID: Int,
        customerEmail: String? = nil
    ) {
        self.schema = Self.currentSchema
        self.key = key
        self.instanceID = instanceID
        self.instanceName = instanceName
        self.activatedAt = activatedAt
        self.lastValidatedAt = lastValidatedAt
        self.refusedAt = refusedAt
        self.status = status
        self.storeID = storeID
        self.productID = productID
        self.variantID = variantID
        self.customerEmail = customerEmail
    }

    /// Safe to show in a menu or a log: `A1B2****-****-****-****-****C3D4`.
    public var maskedKey: String {
        guard key.count > 8 else { return String(repeating: "*", count: key.count) }
        return key.prefix(4) + String(repeating: "*", count: key.count - 8) + key.suffix(4)
    }
}
