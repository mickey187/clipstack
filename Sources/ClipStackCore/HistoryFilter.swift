import Foundation

/// The buckets the popup can narrow the history down to.
///
/// `text` includes links on purpose — a URL is still text, and `link` is a
/// shortcut to the URLs rather than an exclusive bucket that hides them.
public enum ItemCategory: String, CaseIterable, Codable, Sendable {
    case all
    case text
    case image
    case link

    public var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .image: return "Images"
        case .link: return "Links"
        }
    }

    public func contains(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.type == .text
        case .image: return item.type == .image
        case .link: return item.isLink
        }
    }
}

public extension Array where Element == ClipboardItem {
    /// Narrowed by category and query, preserving the receiver's order — the
    /// store is already newest-first, and the popup partitions pinned from
    /// recent afterwards.
    func filtered(category: ItemCategory, query: String) -> [ClipboardItem] {
        filter { category.contains($0) && $0.matches(query: query) }
    }
}
