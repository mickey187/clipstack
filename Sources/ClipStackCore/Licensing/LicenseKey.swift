import Foundation

/// Cleans up what the user pasted before it costs a network round trip.
public enum LicenseKey {
    /// Trims, and removes whitespace that survived a copy out of an email — people
    /// routinely paste a key with a trailing newline or a line break through the middle.
    ///
    /// Case is deliberately **not** changed. Lemon Squeezy issues lowercase UUIDs and
    /// makes no documented promise about case-insensitive lookup, so normalising it
    /// would risk turning a good key into a rejected one.
    public static func normalized(_ raw: String) -> String? {
        let stripped = raw.filter { !$0.isWhitespace }
        guard isPlausible(stripped) else { return nil }
        return stripped
    }

    /// A cheap sanity check, not validation — the server decides.
    ///
    /// Intentionally loose: Lemon Squeezy's default keys are UUIDs, but stores can be
    /// configured to issue shorter custom formats, so anything key-shaped passes. The
    /// only job here is to catch an empty field or a stray sentence without a round trip.
    private static func isPlausible(_ text: String) -> Bool {
        guard text.count >= 8, text.count <= 64 else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// The Lemon Squeezy product this build belongs to.
///
/// Checking this is not optional. The License API is unauthenticated, so without it a
/// licence key for *any other Lemon Squeezy product in the world* would activate
/// ClipStack. These are identifiers, not secrets — there is nothing to protect by
/// hiding them.
public struct ProductIdentity: Equatable, Sendable {
    public let storeID: Int
    public let productID: Int
    public let variantIDs: Set<Int>

    public init(storeID: Int, productID: Int, variantIDs: Set<Int>) {
        self.storeID = storeID
        self.productID = productID
        self.variantIDs = variantIDs
    }

    public func matches(_ meta: LemonSqueezyMeta) -> Bool {
        meta.storeID == storeID
            && meta.productID == productID
            && variantIDs.contains(meta.variantID)
    }

    // TODO: fill in from the Lemon Squeezy dashboard once the product exists.
    // Until these are real, activation cannot succeed — which is the safe failure.
    public static let clipStack = ProductIdentity(
        storeID: 0,
        productID: 0,
        variantIDs: []
    )

    /// Guards against shipping the placeholder above.
    public var isConfigured: Bool {
        storeID != 0 && productID != 0 && !variantIDs.isEmpty
    }
}
