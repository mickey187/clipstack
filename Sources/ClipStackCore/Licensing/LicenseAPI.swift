import Foundation

/// The network, injected.
///
/// Keeping this a closure is what lets the whole licensing state machine live in
/// ClipStackCore and be unit-tested without URLSession, a server, or a network.
/// Returning an optional rather than throwing matches `UpdateChecker`'s house style:
/// there is exactly one failure, and it is never fatal.
public typealias LicenseTransport = @Sendable (URLRequest) async -> (Data, Int)?

public struct LicenseAPI: Sendable {
    public static let base = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!

    private let product: ProductIdentity
    private let transport: LicenseTransport

    public init(product: ProductIdentity, transport: @escaping LicenseTransport) {
        self.product = product
        self.transport = transport
    }

    // MARK: - Activate

    public func activate(
        key: String,
        instanceName: String,
        now: Date = Date()
    ) async -> ActivationOutcome {
        guard product.isConfigured else { return .refused(.notConfigured) }

        guard let (data, status) = await post(
            "activate",
            fields: ["license_key": key, "instance_name": instanceName]
        ) else { return .unreachable }

        // A 4xx from Lemon Squeezy still carries a JSON body explaining the refusal,
        // so decode first and only treat an unreadable body as unreachable.
        guard let payload = try? JSONDecoder().decode(ActivationPayload.self, from: data) else {
            return .unreachable
        }
        guard (200...499).contains(status) else { return .unreachable }

        let (outcome, stray) = payload.outcome(product: product, now: now)

        // Someone else's key just burned one of *their* activation slots on our
        // failed attempt. Hand it straight back.
        if let stray {
            _ = await deactivate(key: key, instanceID: stray)
        }
        return outcome
    }

    // MARK: - Validate

    public func validate(key: String, instanceID: String) async -> ValidationOutcome {
        guard product.isConfigured else { return .unreachable }

        guard let (data, status) = await post(
            "validate",
            fields: ["license_key": key, "instance_id": instanceID]
        ) else { return .unreachable }

        guard let payload = try? JSONDecoder().decode(ValidationPayload.self, from: data),
              (200...499).contains(status)
        else { return .unreachable }

        let keyStatus = payload.licenseKey?.status ?? .unknown

        if payload.valid {
            // Belt and braces: a valid response for someone else's product should never
            // keep us licensed, even though activation already checked this.
            if let meta = payload.meta, !product.matches(meta) {
                return .refused(.disabled)
            }
            return .valid(keyStatus)
        }

        // The key is fine but this Mac's instance is gone — the user deactivated it
        // from the dashboard, or Lemon Squeezy pruned it. Recoverable, not a refusal.
        if keyStatus == .active || payload.instance == nil {
            return .unknownInstance
        }
        guard keyStatus.isDefinitivelyBad else { return .unknownInstance }
        return .refused(keyStatus)
    }

    // MARK: - Deactivate

    @discardableResult
    public func deactivate(key: String, instanceID: String) async -> Bool {
        guard let (data, status) = await post(
            "deactivate",
            fields: ["license_key": key, "instance_id": instanceID]
        ) else { return false }
        guard (200...299).contains(status) else { return false }
        struct Payload: Decodable { let deactivated: Bool }
        return (try? JSONDecoder().decode(Payload.self, from: data))?.deactivated ?? false
    }

    // MARK: - Plumbing

    private func post(_ path: String, fields: [String: String]) async -> (Data, Int)? {
        var request = URLRequest(url: Self.base.appendingPathComponent(path), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(fields)
        return await transport(request)
    }

    static func formEncoded(_ fields: [String: String]) -> Data {
        // Sorted so the body is deterministic and therefore assertable in tests.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.keys.sorted().map { name in
            let value = fields[name]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
