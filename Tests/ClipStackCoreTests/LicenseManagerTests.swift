import Foundation
import Testing
@testable import ClipStackCore

private let day: TimeInterval = 86_400
private let start = Date(timeIntervalSince1970: 1_700_000_000)
private let ourProduct = ProductIdentity(storeID: 42, productID: 100, variantIDs: [200])
private let goodKey = "aaaabbbb-cccc-dddd-eeee-ffff00001111"

// MARK: - Test doubles

/// An in-memory `SecretStore` that can also pretend the Keychain is unreadable.
private final class FakeSecrets: SecretStore, @unchecked Sendable {
    var items: [String: Data] = [:]
    var isUnavailable = false
    private(set) var writes = 0

    func read(service: String, account: String) -> SecretReadResult {
        if isUnavailable { return .unavailable }
        guard let data = items["\(service)/\(account)"] else { return .absent }
        return .found(data)
    }

    func write(_ data: Data, service: String, account: String) -> Bool {
        if isUnavailable { return false }
        writes += 1
        items["\(service)/\(account)"] = data
        return true
    }

    func delete(service: String, account: String) -> Bool {
        items.removeValue(forKey: "\(service)/\(account)") != nil
    }

    var hasTrial: Bool { items["\(SecretKeys.trialService)/\(SecretKeys.trialAccount)"] != nil }
    var hasLicense: Bool { items["\(SecretKeys.licenseService)/\(SecretKeys.licenseAccount)"] != nil }
}

private func activationJSON(activated: Bool = true, storeID: Int = 42, error: String? = nil) -> Data {
    let errorField = error.map { "\"\($0)\"" } ?? "null"
    return Data("""
    { "activated": \(activated), "error": \(errorField),
      "license_key": { "status": "active", "key": "\(goodKey)",
                       "activation_limit": 3, "activation_usage": 1 },
      "instance": { "id": "inst-123", "name": "ClipStack — Test Mac" },
      "meta": { "store_id": \(storeID), "product_id": 100, "variant_id": 200,
                "customer_email": "a@example.com" } }
    """.utf8)
}

private func validationJSON(valid: Bool, status: String) -> Data {
    Data("""
    { "valid": \(valid), "error": null,
      "license_key": { "status": "\(status)", "key": "\(goodKey)",
                       "activation_limit": 3, "activation_usage": 1 },
      "instance": { "id": "inst-123", "name": "Mac" },
      "meta": { "store_id": 42, "product_id": 100, "variant_id": 200,
                "customer_email": null } }
    """.utf8)
}

/// Routes by URL path so a single manager can be driven through several calls.
private func router(
    _ handler: @escaping @Sendable (String) -> (Data, Int)?
) -> LicenseTransport {
    { request in handler(request.url?.lastPathComponent ?? "") }
}

@MainActor
private func makeManager(
    secrets: FakeSecrets,
    clock: @escaping @Sendable () -> Date = { start },
    transport: @escaping LicenseTransport = { _ in nil }
) -> LicenseManager {
    LicenseManager(
        secrets: secrets,
        api: LicenseAPI(product: ourProduct, transport: transport),
        instanceName: "ClipStack — Test Mac",
        now: clock
    )
}

// MARK: - Trial bootstrap

@Test @MainActor
func aFirstLaunchWritesATrialRecordAndReportsFourteenDays() {
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets)
    manager.start()

    #expect(manager.entitlement == .trial(daysRemaining: 14))
    #expect(secrets.hasTrial)
}

@Test @MainActor
func aSecondLaunchReusesTheExistingTrialRatherThanRestartingIt() {
    let secrets = FakeSecrets()
    makeManager(secrets: secrets, clock: { start }).start()

    let tenDaysLater = start.addingTimeInterval(10 * day)
    let second = makeManager(secrets: secrets, clock: { tenDaysLater })
    second.start()

    #expect(second.entitlement == .trial(daysRemaining: 4))
}

@Test @MainActor
func anUnavailableKeychainDoesNotWriteANewTrialRecord() {
    // A cancelled Keychain prompt must not hand out a fresh trial every launch.
    let secrets = FakeSecrets()
    secrets.isUnavailable = true

    let manager = makeManager(secrets: secrets)
    manager.start()

    #expect(manager.storageUnavailable)
    #expect(secrets.writes == 0)
    #expect(manager.entitlement.capturesClipboard)
}

@Test @MainActor
func aDeletedAppThatLeftItsTrialBehindDoesNotGetAFreshTrial() {
    let secrets = FakeSecrets()
    makeManager(secrets: secrets, clock: { start }).start()

    // Reinstall: the app is gone but the Keychain item is not.
    let later = start.addingTimeInterval(20 * day)
    let reinstalled = makeManager(secrets: secrets, clock: { later })
    reinstalled.start()

    #expect(reinstalled.entitlement == .trialExpired)
}

@Test @MainActor
func theTrialExpiresAndStopsCapture() {
    let secrets = FakeSecrets()
    makeManager(secrets: secrets, clock: { start }).start()

    let later = start.addingTimeInterval(15 * day)
    let manager = makeManager(secrets: secrets, clock: { later })
    manager.start()

    #expect(manager.entitlement == .trialExpired)
    #expect(!manager.entitlement.capturesClipboard)
}

// MARK: - Activation

@Test @MainActor
func aSuccessfulActivationStoresTheLicenceAndEnablesCapture() async {
    let secrets = FakeSecrets()
    let expired = start.addingTimeInterval(30 * day)
    makeManager(secrets: secrets, clock: { start }).start()

    let manager = makeManager(
        secrets: secrets, clock: { expired },
        transport: router { _ in (activationJSON(), 200) }
    )
    manager.start()
    #expect(manager.entitlement == .trialExpired)

    let result = await manager.activate(goodKey)
    #expect(result.isSuccess)
    #expect(manager.entitlement == .licensed)
    #expect(manager.entitlement.capturesClipboard)
    #expect(secrets.hasLicense)
}

@Test @MainActor
func aLicenceSurvivesARelaunch() async {
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets, transport: router { _ in (activationJSON(), 200) })
    manager.start()
    _ = await manager.activate(goodKey)

    let relaunched = makeManager(secrets: secrets, clock: { start.addingTimeInterval(90 * day) })
    relaunched.start()
    #expect(relaunched.entitlement == .licensed)
}

@Test @MainActor
func aMalformedKeyIsRejectedWithoutTouchingTheNetwork() async {
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets, transport: router { _ in
        Issue.record("must not reach the network for a malformed key")
        return nil
    })
    manager.start()

    #expect(await manager.activate("  ").error == .malformedKey)
    #expect(await manager.activate("not a licence key at all!").error == .malformedKey)
}

@Test @MainActor
func aKeyPastedWithStrayWhitespaceStillActivates() async {
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets, transport: router { _ in (activationJSON(), 200) })
    manager.start()

    #expect(await manager.activate("  \(goodKey)\n").isSuccess)
}

@Test @MainActor
func activatingAKeyForAnotherProductStoresNothingAndReturnsTheSlot() async {
    let secrets = FakeSecrets()
    let deactivated = Locked(false)

    let manager = makeManager(secrets: secrets, transport: router { path in
        switch path {
        case "activate":
            return (activationJSON(storeID: 999), 200)
        case "deactivate":
            deactivated.set(true)
            return (Data(#"{"deactivated": true}"#.utf8), 200)
        default:
            return nil
        }
    })
    manager.start()

    #expect(await manager.activate(goodKey).error == .wrongProduct)
    #expect(!secrets.hasLicense)
    // We burned an activation on a stranger's licence; hand it straight back.
    #expect(deactivated.value)
}

@Test @MainActor
func aNetworkFailureDuringActivationChangesNoState() async {
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets, transport: router { _ in nil })
    manager.start()

    let before = manager.entitlement
    #expect(await manager.activate(goodKey).isFailure)
    #expect(manager.entitlement == before)
    #expect(!secrets.hasLicense)
}

// MARK: - Revalidation

@Test @MainActor
func aFailedRevalidationDoesNotRevokeTheLicence() async {
    let secrets = FakeSecrets()
    let calls = Locked(0)
    let manager = makeManager(secrets: secrets, transport: router { path in
        if path == "activate" { return (activationJSON(), 200) }
        calls.set(calls.value + 1)
        return nil // validate is offline
    })
    manager.start()
    _ = await manager.activate(goodKey)

    await manager.revalidateNow()
    #expect(manager.entitlement == .licensed)
}

@Test @MainActor
func aDefinitiveRefusalOpensTheGraceWindowRatherThanLockingImmediately() async {
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets, transport: router { path in
        path == "activate"
            ? (activationJSON(), 200)
            : (validationJSON(valid: false, status: "disabled"), 200)
    })
    manager.start()
    _ = await manager.activate(goodKey)

    await manager.revalidateNow()

    #expect(manager.entitlement == .licenseProblem(daysRemaining: 7))
    #expect(manager.entitlement.capturesClipboard)
}

@Test @MainActor
func aRefusedLicenceStopsCapturingOnceGraceRunsOut() async {
    let secrets = FakeSecrets()
    let clock = Locked(start)
    let manager = makeManager(
        secrets: secrets, clock: { clock.value },
        transport: router { path in
            path == "activate"
                ? (activationJSON(), 200)
                : (validationJSON(valid: false, status: "disabled"), 200)
        }
    )
    manager.start()
    _ = await manager.activate(goodKey)
    await manager.revalidateNow()

    clock.set(start.addingTimeInterval(8 * day))
    let relaunched = makeManager(secrets: secrets, clock: { clock.value })
    relaunched.start()

    #expect(relaunched.entitlement == .licenseRevoked)
    #expect(!relaunched.entitlement.capturesClipboard)
}

@Test @MainActor
func aLaterValidResponseClearsAnEarlierRefusal() async {
    let secrets = FakeSecrets()
    let disabled = Locked(true)
    let manager = makeManager(secrets: secrets, transport: router { path in
        if path == "activate" { return (activationJSON(), 200) }
        return (validationJSON(valid: !disabled.value,
                               status: disabled.value ? "disabled" : "active"), 200)
    })
    manager.start()
    _ = await manager.activate(goodKey)

    await manager.revalidateNow()
    #expect(manager.entitlement == .licenseProblem(daysRemaining: 7))

    disabled.set(false)
    await manager.revalidateNow()
    #expect(manager.entitlement == .licensed)
}

@Test @MainActor
func aMissingInstanceIsSilentlyReactivatedRatherThanRefused() async {
    // The user deactivated this Mac from their dashboard. They should never notice.
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets, transport: router { path in
        path == "activate"
            ? (activationJSON(), 200)
            : (validationJSON(valid: false, status: "active"), 200)
    })
    manager.start()
    _ = await manager.activate(goodKey)

    await manager.revalidateNow()
    #expect(manager.entitlement == .licensed)
}

// MARK: - Deactivation

@Test @MainActor
func deactivatingThisMacFallsBackToTheTrialState() async {
    let secrets = FakeSecrets()
    let manager = makeManager(secrets: secrets, transport: router { path in
        path == "activate"
            ? (activationJSON(), 200)
            : (Data(#"{"deactivated": true}"#.utf8), 200)
    })
    manager.start()
    _ = await manager.activate(goodKey)
    #expect(manager.entitlement == .licensed)

    await manager.deactivateThisMac()
    #expect(!secrets.hasLicense)
    #expect(manager.entitlement == .trial(daysRemaining: 14))
}

// MARK: - Helpers

/// Minimal mutable box so closures can be `@Sendable` without actor hops in tests.
private final class Locked<Value>: @unchecked Sendable {
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { stored }
    func set(_ newValue: Value) { stored = newValue }
}

private extension Result where Success == Void, Failure == ActivationError {
    var isSuccess: Bool { if case .success = self { true } else { false } }
    var isFailure: Bool { !isSuccess }
    var error: ActivationError? { if case .failure(let error) = self { error } else { nil } }
}
