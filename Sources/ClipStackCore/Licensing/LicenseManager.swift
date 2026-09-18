import Foundation
import Observation

/// Owns the trial clock and the licence, and answers one question: what is the app
/// allowed to do right now.
///
/// Lives in ClipStackCore rather than the app target on purpose. Every dependency —
/// storage, network, and the clock — is injected, so the whole state machine is
/// testable without AppKit, without the Keychain, and without a network.
///
/// Failure philosophy follows `UpdateChecker`: background work fails silently and
/// changes nothing. The one exception is `activate(_:)`, because a user who just typed
/// a licence key is owed an answer.
@MainActor
@Observable
public final class LicenseManager {
    public private(set) var entitlement: Entitlement = .trial(daysRemaining: 14)
    public private(set) var isActivating = false

    /// Set when the Keychain could not be read at all. Nothing is ever written while
    /// this is true, so a locked Keychain can neither reset a trial nor lose a licence.
    public private(set) var storageUnavailable = false

    private let secrets: any SecretStore
    private let defaults: (any LicenseDefaults)?
    private let api: LicenseAPI
    private let now: @Sendable () -> Date
    private let instanceName: String

    private var trial: TrialRecord?
    private var license: LicenseRecord?
    private var isRevalidating = false

    /// Persisted to the Keychain only when the mark has moved this far, to keep writes
    /// rare — the heartbeat runs every 30 minutes but almost never needs to save.
    private static let persistThreshold: TimeInterval = 3_600
    private var lastPersistedMark: Date?

    public init(
        secrets: any SecretStore,
        defaults: (any LicenseDefaults)? = nil,
        api: LicenseAPI,
        instanceName: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.secrets = secrets
        self.defaults = defaults
        self.api = api
        self.instanceName = instanceName
        self.now = now
    }

    // MARK: - Lifecycle

    /// Loads both records, starts the trial if this is genuinely a first launch, and
    /// computes the initial entitlement.
    public func start() {
        loadLicense()
        loadTrial()
        observeClock(persist: true)
        recompute()
    }

    /// Moves the trial's high water mark forward. Cheap; call it freely.
    public func observeClock(persist: Bool = false) {
        guard !storageUnavailable, var trial else { return }
        let moved = trial.observe(now: now())
        self.trial = trial
        defaults?.saveTrialMirror(trial)
        guard moved else { return }

        let due = lastPersistedMark.map {
            trial.highWaterMark.timeIntervalSince($0) >= Self.persistThreshold
        } ?? true
        if persist || due {
            persistTrial()
        }
        recompute()
    }

    /// Unconditional save, for `applicationWillTerminate`.
    public func persistTrialNow() {
        guard !storageUnavailable, let trial else { return }
        _ = trial
        persistTrial()
    }

    // MARK: - Activation

    public func activate(_ rawKey: String) async -> Result<Void, ActivationError> {
        guard !isActivating else { return .failure(.server("Already activating.")) }
        guard let key = LicenseKey.normalized(rawKey) else { return .failure(.malformedKey) }

        isActivating = true
        defer { isActivating = false }

        switch await api.activate(key: key, instanceName: instanceName, now: now()) {
        case .activated(let record):
            license = record
            writeLicense(record)
            recompute()
            return .success(())
        case .refused(let error):
            return .failure(error)
        case .unreachable:
            return .failure(.server("Couldn't reach the licence server. Check your connection and try again."))
        }
    }

    /// Hands this Mac's activation slot back, so it can be used on another machine.
    public func deactivateThisMac() async {
        guard let license else { return }
        await api.deactivate(key: license.key, instanceID: license.instanceID)
        // The local record goes regardless of what the server said: if the call failed,
        // leaving a licence the user has explicitly disowned would be worse.
        self.license = nil
        secrets.delete(service: SecretKeys.licenseService, account: SecretKeys.licenseAccount)
        recompute()
    }

    // MARK: - Revalidation

    /// Sync entry point, mirroring `UpdateChecker.checkIfDue()`. Safe on every launch.
    public func revalidateIfDue() {
        guard license != nil else { return }
        if let last = defaults?.lastLicenseCheck(),
           now().timeIntervalSince(last) < EntitlementPolicy.revalidationInterval {
            return
        }
        Task { await revalidateNow() }
    }

    /// Checks regardless of the throttle. Used by the tests and by a manual re-check.
    public func revalidateNow() async {
        guard !isRevalidating, let license else { return }
        isRevalidating = true
        defer { isRevalidating = false }

        switch await api.validate(key: license.key, instanceID: license.instanceID) {
        case .valid(let status):
            var updated = license
            updated.status = status
            updated.lastValidatedAt = now()
            updated.refusedAt = nil
            self.license = updated
            writeLicense(updated)
            defaults?.setLastLicenseCheck(now())

        case .unknownInstance:
            // This Mac's instance is gone. Re-activate silently; the user does not need
            // to know their dashboard was tidied up.
            switch await api.activate(key: license.key, instanceName: instanceName, now: now()) {
            case .activated(let record):
                self.license = record
                writeLicense(record)
                defaults?.setLastLicenseCheck(now())
            case .refused:
                markRefused()
                defaults?.setLastLicenseCheck(now())
            case .unreachable:
                break // Silent. Try again next launch.
            }

        case .refused:
            markRefused()
            defaults?.setLastLicenseCheck(now())

        case .unreachable:
            // The whole point of the design: a failed request never costs anyone
            // their licence, and the throttle is not stamped so we retry next launch.
            break
        }
        recompute()
    }

    private func markRefused() {
        guard var license, license.refusedAt == nil else { return }
        license.refusedAt = now()
        self.license = license
        writeLicense(license)
    }

    // MARK: - Storage

    private func loadLicense() {
        switch secrets.read(service: SecretKeys.licenseService, account: SecretKeys.licenseAccount) {
        case .found(let data):
            // A corrupt licence record is discarded rather than fatal: the user can
            // re-activate, and the trial evaluation below still applies.
            license = try? JSONDecoder().decode(LicenseRecord.self, from: data)
        case .absent:
            license = nil
        case .unavailable:
            license = nil
            storageUnavailable = true
        }
    }

    private func loadTrial() {
        switch secrets.read(service: SecretKeys.trialService, account: SecretKeys.trialAccount) {
        case .found(let data):
            let stored = try? JSONDecoder().decode(TrialRecord.self, from: data)
            trial = stored?.merged(withMirror: defaults?.loadTrialMirror())
            lastPersistedMark = trial?.highWaterMark

        case .absent:
            // The ONLY branch that may start a trial. A genuine first launch.
            guard !storageUnavailable else { return }
            var fresh = TrialRecord(installedAt: now())
            if let mirrored = defaults?.loadTrialMirror() {
                // A reinstall that left the mirror behind resumes the old trial.
                fresh = fresh.merged(withMirror: mirrored)
            }
            trial = fresh
            persistTrial()

        case .unavailable:
            // Locked Keychain or a cancelled prompt. Assume a full trial for this
            // session and write nothing at all.
            trial = nil
            storageUnavailable = true
        }
    }

    private func persistTrial() {
        guard let trial, let data = try? JSONEncoder().encode(trial) else { return }
        secrets.write(data, service: SecretKeys.trialService, account: SecretKeys.trialAccount)
        defaults?.saveTrialMirror(trial)
        lastPersistedMark = trial.highWaterMark
    }

    private func writeLicense(_ record: LicenseRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        secrets.write(data, service: SecretKeys.licenseService, account: SecretKeys.licenseAccount)
    }

    private func recompute() {
        entitlement = EntitlementPolicy.evaluate(trial: trial, license: license, now: now())
    }
}
