import Foundation

/// A dotted release version, tolerant of the `v` prefix GitHub tags carry.
///
/// Exists mainly so "1.10.0 is newer than 1.9.0" is decided by numbers rather
/// than string ordering, which is the classic way update checks go wrong.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        // Ignore any pre-release/build suffix: "1.2.0-beta.1" compares as 1.2.0.
        let numeric = text.prefix { $0.isNumber || $0 == "." }
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }
        self.components = parsed
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            // Missing trailing components read as zero, so 1.2 == 1.2.0.
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }
}
