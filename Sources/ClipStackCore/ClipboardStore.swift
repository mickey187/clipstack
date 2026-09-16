import Foundation
import Observation

/// The clipboard history: an in-memory list, newest first, backed by a JSON file
/// plus a directory of PNG blobs for images.
///
/// Deliberately free of AppKit so the interesting logic — dedupe, pinning,
/// eviction, persistence — can be unit tested.
@MainActor
@Observable
public final class ClipboardStore {
    /// Newest first. Pinned items stay in recency order here; the UI partitions them.
    public private(set) var items: [ClipboardItem] = []

    /// How many *unpinned* items to keep. Pinned items never count toward this.
    public var maxUnpinnedItems: Int

    private let directory: URL
    private let historyURL: URL
    private let blobsURL: URL
    private var saveTask: Task<Void, Never>?

    /// Seconds to coalesce writes over, so a burst of copies is one disk write.
    private let saveDebounce: Duration

    public init(
        directory: URL? = nil,
        maxUnpinnedItems: Int = 50,
        saveDebounce: Duration = .seconds(1)
    ) {
        self.directory = directory ?? Self.defaultDirectory()
        self.maxUnpinnedItems = maxUnpinnedItems
        self.saveDebounce = saveDebounce
        self.historyURL = self.directory.appendingPathComponent("history.json")
        self.blobsURL = self.directory.appendingPathComponent("Blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClipStack", isDirectory: true)
    }

    // MARK: - Mutation

    /// Adds an item, or promotes the existing copy of the same content to the top.
    ///
    /// Returns the item as it now lives in the store — the promoted original when
    /// this was a duplicate, which matters because the original owns the blob.
    @discardableResult
    public func insert(_ item: ClipboardItem) -> ClipboardItem {
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: index)
            existing.createdAt = item.createdAt
            items.insert(existing, at: 0)
            scheduleSave()
            return existing
        }
        items.insert(item, at: 0)
        evictIfNeeded()
        scheduleSave()
        return item
    }

    /// Adds an image, writing its PNG to the blob directory first. If the same
    /// image is already in history the blob is not rewritten.
    @discardableResult
    public func insertImage(
        pngData: Data,
        thumbnailData: Data?,
        pixelWidth: Int,
        pixelHeight: Int,
        createdAt: Date = Date()
    ) -> ClipboardItem {
        let hash = ClipboardItem.hash(of: pngData)
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = items.remove(at: index)
            existing.createdAt = createdAt
            items.insert(existing, at: 0)
            scheduleSave()
            return existing
        }

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        try? pngData.write(to: blobsURL.appendingPathComponent(fileName), options: .atomic)

        let item = ClipboardItem(
            id: id,
            type: .image,
            imageFileName: fileName,
            thumbnailData: thumbnailData,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            contentHash: hash,
            createdAt: createdAt
        )
        items.insert(item, at: 0)
        evictIfNeeded()
        scheduleSave()
        return item
    }

    public func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        // Unpinning can push us back over the cap.
        evictIfNeeded()
        scheduleSave()
    }

    public func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        scheduleSave()
    }

    /// Clears everything except pinned items — what the popup's Clear button does.
    public func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        scheduleSave()
    }

    /// Clears everything, pinned included — what the menu bar's Clear History does.
    public func clearAll() {
        items.removeAll()
        scheduleSave()
    }

    private func evictIfNeeded() {
        var unpinnedCount = items.reduce(0) { $0 + ($1.isPinned ? 0 : 1) }
        while unpinnedCount > maxUnpinnedItems {
            guard let lastUnpinned = items.lastIndex(where: { !$0.isPinned }) else { break }
            items.remove(at: lastUnpinned)
            unpinnedCount -= 1
        }
    }

    // MARK: - Blobs

    public func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return blobsURL.appendingPathComponent(name)
    }

    /// Full-resolution PNG bytes, read lazily — only at paste time.
    public func imageData(for item: ClipboardItem) -> Data? {
        guard let url = imageURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Persistence

    public func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ClipboardItem].self, from: data) else { return }
        // Drop images whose blob went missing (manual deletion, failed write).
        items = decoded.filter { item in
            guard item.type == .image else { return true }
            guard let url = imageURL(for: item) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    public func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [saveDebounce] in
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
        collectGarbageBlobs()
    }

    /// Deletes PNGs no live item references — otherwise evicted images leak disk forever.
    private func collectGarbageBlobs() {
        let referenced = Set(items.compactMap(\.imageFileName))
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: blobsURL, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !referenced.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
