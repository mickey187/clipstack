import CryptoKit
import Foundation

public enum ItemType: String, Codable, Sendable {
    case text
    case image
}

/// One entry in the clipboard history.
///
/// Image bytes deliberately live outside this struct: `imageFileName` points at a
/// PNG in the store's `Blobs/` directory, and only the small `thumbnailData` is
/// held in memory. Inlining full images would base64 them into the history JSON
/// and decode them all at launch, which blows the idle memory budget.
public struct ClipboardItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let type: ItemType
    public let textValue: String?
    public let imageFileName: String?
    public let thumbnailData: Data?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    /// SHA256 of the underlying content. The dedupe key.
    public let contentHash: String
    public var createdAt: Date
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        type: ItemType,
        textValue: String? = nil,
        imageFileName: String? = nil,
        thumbnailData: Data? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        contentHash: String,
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.type = type
        self.textValue = textValue
        self.imageFileName = imageFileName
        self.thumbnailData = thumbnailData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    public static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(of string: String) -> String {
        hash(of: Data(string.utf8))
    }

    /// Longest text we are willing to keep. Guards against someone copying a
    /// multi-megabyte log and dragging the whole history file down with it.
    public static let maxTextLength = 100_000

    public static func text(_ value: String, createdAt: Date = Date()) -> ClipboardItem {
        let truncated = value.count > maxTextLength
            ? String(value.prefix(maxTextLength))
            : value
        return ClipboardItem(
            type: .text,
            textValue: truncated,
            contentHash: hash(of: truncated),
            createdAt: createdAt
        )
    }

    /// A single-line preview suitable for menus and accessibility labels.
    public var previewText: String {
        switch type {
        case .text:
            let collapsed = (textValue ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? "(blank)" : collapsed
        case .image:
            if let w = pixelWidth, let h = pixelHeight {
                return "Image \(w) × \(h)"
            }
            return "Image"
        }
    }

    /// Whether the whole entry is a single URL.
    ///
    /// Deliberately "is a link" rather than "contains a link": people copy URLs
    /// on their own, and substring matching would file half of all prose under
    /// Links.
    public var isLink: Bool {
        guard type == .text, let value = textValue else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }

        if trimmed.lowercased().hasPrefix("www.") { return true }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return false }
        return true
    }

    /// Whether this entry should survive a search for `query`.
    ///
    /// Images match only the empty query: matching them on `previewText` would
    /// surface every screenshot in the history for the query "image".
    public func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let value = textValue else { return false }
        return value.localizedStandardContains(trimmed)
    }
}
