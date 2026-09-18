import Foundation
import Testing
@testable import ClipStackCore

private let day: TimeInterval = 86_400
private let trialLength = EntitlementPolicy.trialLength
private let start = Date(timeIntervalSince1970: 1_700_000_000)

@Test
func aFreshTrialHasFourteenDaysLeftOnTheDayItStarts() {
    let record = TrialRecord(installedAt: start)
    #expect(record.daysRemaining(at: start, trialLength: trialLength) == 14)
    #expect(!record.hasExpired(at: start, trialLength: trialLength))
}

@Test
func theTrialCountsDownOneDayAtATime() {
    var record = TrialRecord(installedAt: start)
    for elapsed in 0..<14 {
        let now = start.addingTimeInterval(Double(elapsed) * day)
        record.observe(now: now)
        #expect(record.daysRemaining(at: now, trialLength: trialLength) == 14 - elapsed)
    }
}

@Test
func theLastDayOfTheTrialReadsAsOneDayNotZero() {
    var record = TrialRecord(installedAt: start)
    // 13.5 days in: still inside the trial, so it must not say "0 days left".
    let now = start.addingTimeInterval(13.5 * day)
    record.observe(now: now)
    #expect(record.daysRemaining(at: now, trialLength: trialLength) == 1)
    #expect(!record.hasExpired(at: now, trialLength: trialLength))
}

@Test
func theTrialExpiresOnceFourteenDaysHavePassed() {
    var record = TrialRecord(installedAt: start)
    let now = start.addingTimeInterval(14 * day)
    record.observe(now: now)
    #expect(record.hasExpired(at: now, trialLength: trialLength))
    #expect(record.daysRemaining(at: now, trialLength: trialLength) == 0)
}

@Test
func aClockMovedBackwardsDoesNotBuyMoreTrial() {
    var record = TrialRecord(installedAt: start)
    let tenDaysIn = start.addingTimeInterval(10 * day)
    record.observe(now: tenDaysIn)

    // The user winds the clock back to the day they installed it.
    let rolledBack = start
    record.observe(now: rolledBack)

    #expect(record.highWaterMark == tenDaysIn)
    #expect(record.daysRemaining(at: rolledBack, trialLength: trialLength) == 4)
}

@Test
func anExpiredTrialStaysExpiredAfterTheClockIsRolledBack() {
    var record = TrialRecord(installedAt: start)
    record.observe(now: start.addingTimeInterval(20 * day))
    record.observe(now: start)
    #expect(record.hasExpired(at: start, trialLength: trialLength))
}

@Test
func theHighWaterMarkSurvivesMovingTheClockBackAndForwardAgain() {
    var record = TrialRecord(installedAt: start)
    record.observe(now: start.addingTimeInterval(10 * day))
    record.observe(now: start.addingTimeInterval(2 * day))
    record.observe(now: start.addingTimeInterval(11 * day))
    #expect(record.highWaterMark == start.addingTimeInterval(11 * day))
}

@Test
func observeReportsWhetherItActuallyMovedSoWritesCanBeSkipped() {
    var record = TrialRecord(installedAt: start)
    #expect(record.observe(now: start.addingTimeInterval(day)) == true)
    #expect(record.observe(now: start) == false)
    #expect(record.observe(now: start.addingTimeInterval(day)) == false)
}

@Test
func aLargeJumpForwardConsumesTheTrialPermanently() {
    var record = TrialRecord(installedAt: start)
    record.observe(now: start.addingTimeInterval(365 * day))
    // Back to the real date — the trial is gone and stays gone. Self-inflicted.
    #expect(record.hasExpired(at: start.addingTimeInterval(day), trialLength: trialLength))
}

@Test
func theMirrorCanShortenATrialButNeverExtendIt() {
    var keychain = TrialRecord(installedAt: start.addingTimeInterval(5 * day))
    keychain.observe(now: start.addingTimeInterval(6 * day))

    // A mirror claiming an earlier install and a later mark: both are taken, because
    // both shorten the remaining trial.
    var mirror = TrialRecord(installedAt: start)
    mirror.observe(now: start.addingTimeInterval(9 * day))

    let merged = keychain.merged(withMirror: mirror)
    #expect(merged.installedAt == start)
    #expect(merged.highWaterMark == start.addingTimeInterval(9 * day))

    // And a mirror trying to claim a *later* install gains nothing.
    let flattering = TrialRecord(installedAt: start.addingTimeInterval(13 * day))
    #expect(merged.merged(withMirror: flattering).installedAt == start)
}

@Test
func aTrialRecordRoundTripsThroughJSONUnchanged() throws {
    var record = TrialRecord(installedAt: start)
    record.observe(now: start.addingTimeInterval(3 * day))

    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(TrialRecord.self, from: data)
    #expect(decoded == record)
}

@Test
func aRecordWrittenWithoutAHighWaterMarkDecodesAsNeverRun() throws {
    // Forwards compatibility with any record shape that predates the mark.
    let json = #"{"installedAt": 0}"#
    let decoded = try JSONDecoder().decode(TrialRecord.self, from: Data(json.utf8))
    #expect(decoded.highWaterMark == decoded.installedAt)
}
