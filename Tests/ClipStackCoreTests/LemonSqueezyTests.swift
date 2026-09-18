import Foundation
import Testing
@testable import ClipStackCore

private let now = Date(timeIntervalSince1970: 1_700_000_000)
private let ourProduct = ProductIdentity(storeID: 42, productID: 100, variantIDs: [200])

private func activationJSON(
    activated: Bool = true,
    status: String = "active",
    storeID: Int = 42,
    productID: Int = 100,
    variantID: Int = 200,
    limit: Int = 3,
    usage: Int = 1,
    error: String? = nil
) -> Data {
    let errorField = error.map { "\"\($0)\"" } ?? "null"
    return Data("""
    {
      "activated": \(activated),
      "error": \(errorField),
      "license_key": {
        "id": 1, "status": "\(status)", "key": "aaaabbbb-cccc-dddd-eeee-ffff00001111",
        "activation_limit": \(limit), "activation_usage": \(usage),
        "created_at": "2026-01-01T00:00:00.000000Z", "expires_at": null
      },
      "instance": { "id": "inst-123", "name": "ClipStack — Test Mac",
                    "created_at": "2026-01-01T00:00:00.000000Z" },
      "meta": {
        "store_id": \(storeID), "order_id": 7, "order_item_id": 8,
        "product_id": \(productID), "product_name": "ClipStack",
        "variant_id": \(variantID), "variant_name": "Default",
        "customer_id": 9, "customer_name": "A Person", "customer_email": "a@example.com"
      }
    }
    """.utf8)
}

// MARK: - Decoding

@Test
func aSuccessfulActivationDecodesIntoALicenceRecord() throws {
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: activationJSON())
    let (outcome, stray) = payload.outcome(product: ourProduct, now: now)

    #expect(stray == nil)
    guard case .activated(let record) = outcome else {
        Issue.record("expected activation, got \(outcome)"); return
    }
    #expect(record.instanceID == "inst-123")
    #expect(record.status == .active)
    #expect(record.customerEmail == "a@example.com")
    #expect(record.refusedAt == nil)
}

@Test
func anActivationRefusedForReachingTheLimitReportsTheNumbers() throws {
    let json = activationJSON(activated: false, limit: 3, usage: 3,
                              error: "License key activation limit reached.")
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: json)
    let (outcome, _) = payload.outcome(product: ourProduct, now: now)
    #expect(outcome == .refused(.limitReached(used: 3, limit: 3)))
}

@Test
func aDisabledKeyIsRefusedAsDisabled() throws {
    let json = activationJSON(activated: false, status: "disabled", usage: 1,
                              error: "License key is disabled.")
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: json)
    let (outcome, _) = payload.outcome(product: ourProduct, now: now)
    #expect(outcome == .refused(.disabled))
}

@Test
func anUnrecognisedStatusDecodesAsUnknownRatherThanFailing() throws {
    let json = activationJSON(status: "something_new_upstream")
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: json)
    #expect(payload.licenseKey?.status == .unknown)
    // And "unknown" must never be treated as a refusal.
    #expect(LicenseStatus.unknown.isDefinitivelyBad == false)
}

@Test
func unknownFieldsAddedByTheServerAreIgnored() throws {
    let json = Data("""
    { "activated": true, "error": null, "brand_new_field": {"nested": 1},
      "license_key": { "status": "active", "key": "k", "activation_limit": 3,
                       "activation_usage": 1, "future": "x" },
      "instance": { "id": "inst-9", "name": "Mac", "extra": true },
      "meta": { "store_id": 42, "product_id": 100, "variant_id": 200,
                "customer_email": "a@example.com", "tomorrow": [1,2] } }
    """.utf8)
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: json)
    let (outcome, _) = payload.outcome(product: ourProduct, now: now)
    guard case .activated = outcome else { Issue.record("expected activation"); return }
}

// MARK: - Product verification

@Test
func aResponseFromAnotherStoreIsRejected() throws {
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: activationJSON(storeID: 999))
    let (outcome, stray) = payload.outcome(product: ourProduct, now: now)
    #expect(outcome == .refused(.wrongProduct))
    // And the instance we just created on their licence is handed back.
    #expect(stray == "inst-123")
}

@Test
func aResponseForAnotherProductIsRejected() throws {
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: activationJSON(productID: 999))
    let (outcome, stray) = payload.outcome(product: ourProduct, now: now)
    #expect(outcome == .refused(.wrongProduct))
    #expect(stray == "inst-123")
}

@Test
func aResponseForAnotherVariantIsRejected() throws {
    let payload = try JSONDecoder().decode(ActivationPayload.self, from: activationJSON(variantID: 999))
    let (outcome, _) = payload.outcome(product: ourProduct, now: now)
    #expect(outcome == .refused(.wrongProduct))
}

@Test
func anUnconfiguredBuildRefusesToActivateAtAll() async {
    // Guards against shipping with the placeholder store and product ids.
    #expect(ProductIdentity.clipStack.isConfigured == false)
    let api = LicenseAPI(product: .clipStack, transport: { _ in
        Issue.record("must not reach the network when unconfigured")
        return nil
    })
    let outcome = await api.activate(key: "aaaabbbb-cccc", instanceName: "Mac")
    #expect(outcome == .refused(.notConfigured))
}

// MARK: - Transport failures are never punitive

@Test
func aNetworkFailureIsUnreachableRatherThanRefused() async {
    let api = LicenseAPI(product: ourProduct, transport: { _ in nil })
    #expect(await api.activate(key: "aaaabbbb-cccc", instanceName: "Mac") == .unreachable)
    #expect(await api.validate(key: "aaaabbbb-cccc", instanceID: "i") == .unreachable)
}

@Test
func malformedJSONIsUnreachableRatherThanRefused() async {
    let api = LicenseAPI(product: ourProduct, transport: { _ in (Data("not json".utf8), 200) })
    #expect(await api.activate(key: "aaaabbbb-cccc", instanceName: "Mac") == .unreachable)
}

@Test
func aServerErrorIsUnreachableRatherThanRefused() async {
    // A 500 must never cost someone their licence.
    let api = LicenseAPI(product: ourProduct, transport: { _ in (activationJSON(), 500) })
    #expect(await api.activate(key: "aaaabbbb-cccc", instanceName: "Mac") == .unreachable)
}

@Test
func aRefusalDeliveredWithA404StillCountsAsAnAnswer() async {
    // Lemon Squeezy returns 4xx with a JSON body explaining the refusal.
    let json = activationJSON(activated: false, error: "license_key not found")
    let api = LicenseAPI(product: ourProduct, transport: { _ in (json, 404) })
    #expect(await api.activate(key: "aaaabbbb-cccc", instanceName: "Mac") == .refused(.notFound))
}

// MARK: - Validation

@Test
func aValidateResponseWithValidFalseAndADisabledKeyIsARefusal() async {
    let json = Data("""
    { "valid": false, "error": "disabled",
      "license_key": { "status": "disabled", "key": "k", "activation_limit": 3, "activation_usage": 1 },
      "instance": { "id": "inst-123", "name": "Mac" },
      "meta": { "store_id": 42, "product_id": 100, "variant_id": 200, "customer_email": null } }
    """.utf8)
    let api = LicenseAPI(product: ourProduct, transport: { _ in (json, 200) })
    #expect(await api.validate(key: "k", instanceID: "inst-123") == .refused(.disabled))
}

@Test
func aValidateResponseForAnActiveKeyWithAMissingInstanceIsRecoverable() async {
    // The user deactivated this Mac from their dashboard. Not a refusal.
    let json = Data("""
    { "valid": false, "error": "instance not found",
      "license_key": { "status": "active", "key": "k", "activation_limit": 3, "activation_usage": 0 },
      "instance": null,
      "meta": { "store_id": 42, "product_id": 100, "variant_id": 200, "customer_email": null } }
    """.utf8)
    let api = LicenseAPI(product: ourProduct, transport: { _ in (json, 200) })
    #expect(await api.validate(key: "k", instanceID: "inst-123") == .unknownInstance)
}

@Test
func theRequestBodyIsFormEncodedAndEscaped() {
    let body = LicenseAPI.formEncoded(["license_key": "a b+c", "instance_name": "Mickey's Mac"])
    #expect(String(decoding: body, as: UTF8.self)
        == "instance_name=Mickey%27s%20Mac&license_key=a%20b%2Bc")
}
