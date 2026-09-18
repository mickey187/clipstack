import Foundation

/// The trial clock, as written to the Keychain.
///
/// Consumption is measured from `highWaterMark`, never from "now". A clock moved
/// backwards therefore buys nothing: the mark is already ahead, and `observe(now:)`
/// refuses to walk it back. Moving the clock *forwards* burns the trial for good,
/// which is self-harm and not worth the code it would take to detect.
public struct TrialRecord: Codable, Equatable, Sendable {
    /// Bumped if the shape ever changes, so an old record decodes rather than throws.
    public private(set) var schema: Int
    public let installedAt: Date
    /// The latest moment this install has ever seen. Monotonic by construction.
    public private(set) var highWaterMark: Date

    public static let currentSchema = 1

    public init(installedAt: Date) {
        self.schema = Self.currentSchema
        self.installedAt = installedAt
        self.highWaterMark = installedAt
    }

    /// Records that `now` happened.
    ///
    /// - Returns: `true` when the mark actually moved, so callers can skip a Keychain
    ///   write on the overwhelmingly common no-op.
    @discardableResult
    public mutating func observe(now: Date) -> Bool {
        guard now > highWaterMark else { return false }
        highWaterMark = now
        return true
    }

    /// Trial time consumed so far. Uses the mark, not `now`, so it cannot go down.
    public func elapsed(at now: Date) -> TimeInterval {
        max(highWaterMark, now).timeIntervalSince(installedAt)
    }

    /// Whole days left, rounded up: the first day reads "14", the last reads "1".
    public func daysRemaining(at now: Date, trialLength: TimeInterval) -> Int {
        let left = trialLength - elapsed(at: now)
        guard left > 0 else { return 0 }
        return max(1, Int(ceil(left / 86_400)))
    }

    public func hasExpired(at now: Date, trialLength: TimeInterval) -> Bool {
        elapsed(at: now) >= trialLength
    }

    /// Reconciles the Keychain record with the (untrusted) UserDefaults mirror.
    ///
    /// The mirror can only ever *shorten* a trial — earliest install wins, latest mark
    /// wins — so deleting or editing it is never an advantage.
    public func merged(withMirror mirror: TrialRecord?) -> TrialRecord {
        guard let mirror else { return self }
        var merged = TrialRecord(installedAt: min(installedAt, mirror.installedAt))
        merged.highWaterMark = max(highWaterMark, mirror.highWaterMark)
        return merged
    }

    // Decoding tolerates a missing `schema` from any future/past writer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try container.decodeIfPresent(Int.self, forKey: .schema) ?? Self.currentSchema
        self.installedAt = try container.decode(Date.self, forKey: .installedAt)
        let mark = try container.decodeIfPresent(Date.self, forKey: .highWaterMark)
        // A record with no mark is treated as never having run past its install.
        self.highWaterMark = max(installedAt, mark ?? installedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case schema, installedAt, highWaterMark
    }
}
