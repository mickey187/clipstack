import Foundation
import Testing
@testable import ClipStackCore

private let day: TimeInterval = 86_400
private let start = Date(timeIntervalSince1970: 1_700_000_000)

private func licence(
    refusedAt: Date? = nil,
    lastValidatedAt: Date = start,
    status: LicenseStatus = .active
) -> LicenseRecord {
    LicenseRecord(
        key: "abcd1234-0000-0000-0000-00000000wxyz",
        instanceID: "instance-1",
        instanceName: "ClipStack — Test Mac",
        activatedAt: start,
        lastValidatedAt: lastValidatedAt,
        refusedAt: refusedAt,
        status: status,
        storeID: 1,
        productID: 2,
        variantID: 3
    )
}

// MARK: - Trial

@Test
func aFirstLaunchIsInTrialAndCaptures() {
    let state = EntitlementPolicy.evaluate(
        trial: TrialRecord(installedAt: start), license: nil, now: start
    )
    #expect(state == .trial(daysRemaining: 14))
    #expect(state.capturesClipboard)
}

@Test
func anUnreadableKeychainLeavesCaptureEnabled() {
    // Both records nil is what a locked Keychain or a cancelled prompt looks like.
    // Failing open matters far more than failing closed: the alternative is silently
    // breaking the app for someone who has paid.
    let state = EntitlementPolicy.evaluate(trial: nil, license: nil, now: start)
    #expect(state == .trial(daysRemaining: 14))
    #expect(state.capturesClipboard)
}

@Test
func anExpiredTrialStopsCapture() {
    var trial = TrialRecord(installedAt: start)
    let now = start.addingTimeInterval(15 * day)
    trial.observe(now: now)

    let state = EntitlementPolicy.evaluate(trial: trial, license: nil, now: now)
    #expect(state == .trialExpired)
    #expect(!state.capturesClipboard)
}

// MARK: - Licence outranks the trial

@Test
func anActiveLicenceCapturesEvenWhenTheTrialExpiredLongAgo() {
    var trial = TrialRecord(installedAt: start)
    let now = start.addingTimeInterval(400 * day)
    trial.observe(now: now)

    let state = EntitlementPolicy.evaluate(trial: trial, license: licence(), now: now)
    #expect(state == .licensed)
    #expect(state.capturesClipboard)
}

@Test
func aLicenceNotValidatedForMonthsStillCapturesWhileOffline() {
    // The heart of the offline policy: the age of lastValidatedAt is never consulted.
    let now = start.addingTimeInterval(300 * day)
    let state = EntitlementPolicy.evaluate(
        trial: nil, license: licence(lastValidatedAt: start), now: now
    )
    #expect(state == .licensed)
}

// MARK: - Revocation grace

@Test
func aRefusedLicenceStillCapturesInsideTheGraceWindow() {
    let refusedAt = start
    let now = start.addingTimeInterval(2 * day)
    let state = EntitlementPolicy.evaluate(
        trial: nil, license: licence(refusedAt: refusedAt), now: now
    )
    #expect(state == .licenseProblem(daysRemaining: 5))
    #expect(state.capturesClipboard)
}

@Test
func aRefusedLicenceStopsCapturingOnceTheGraceWindowCloses() {
    let now = start.addingTimeInterval(8 * day)
    let state = EntitlementPolicy.evaluate(
        trial: nil, license: licence(refusedAt: start), now: now
    )
    #expect(state == .licenseRevoked)
    #expect(!state.capturesClipboard)
}

@Test
func clearingARefusalRestoresFullLicensing() {
    let now = start.addingTimeInterval(3 * day)
    var record = licence(refusedAt: start)
    #expect(EntitlementPolicy.evaluate(trial: nil, license: record, now: now).capturesClipboard)

    record.refusedAt = nil
    #expect(EntitlementPolicy.evaluate(trial: nil, license: record, now: now) == .licensed)
}

// MARK: - Presentation

@Test
func aHealthyLicenceShowsNoLicensingUIAnywhere() {
    // Someone who has paid should never be reminded of it.
    #expect(Entitlement.licensed.menuTitle == nil)
    #expect(Entitlement.licensed.bannerMessage == nil)
}

@Test
func theTrialBannerOnlyAppearsInTheLastThreeDays() {
    #expect(Entitlement.trial(daysRemaining: 14).bannerMessage == nil)
    #expect(Entitlement.trial(daysRemaining: 4).bannerMessage == nil)
    #expect(Entitlement.trial(daysRemaining: 3).bannerMessage != nil)
    #expect(Entitlement.trial(daysRemaining: 1).bannerMessage == "Last day of your trial.")
}

@Test
func theTrialMenuTitleReadsNaturallyForASingleDay() {
    #expect(Entitlement.trial(daysRemaining: 1).menuTitle == "1 day left in trial")
    #expect(Entitlement.trial(daysRemaining: 9).menuTitle == "9 days left in trial")
}
