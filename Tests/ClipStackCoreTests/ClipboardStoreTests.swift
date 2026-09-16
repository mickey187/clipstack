import Foundation
import Testing
@testable import ClipStackCore

/// Each test gets its own throwaway support directory so nothing touches the
/// real history in ~/Library/Application Support.
@MainActor
private func makeStore(maxUnpinned: Int = 50) -> (ClipboardStore, URL) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ClipStackTests-\(UUID().uuidString)", isDirectory: true)
    // A long debounce keeps the background save task out of the way; tests that
    // care about persistence call saveNow() explicitly.
    let store = ClipboardStore(directory: dir, maxUnpinnedItems: maxUnpinned, saveDebounce: .seconds(3600))
    return (store, dir)
}

private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
}

// MARK: - Dedupe

@Test @MainActor
func copyingTheSameTextTwiceKeepsOneItemAndMovesItToTop() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    store.insert(.text("hello"))
    store.insert(.text("world"))
    store.insert(.text("hello"))

    #expect(store.items.count == 2)
    #expect(store.items[0].textValue == "hello")
    #expect(store.items[1].textValue == "world")
}

@Test @MainActor
func promotingADuplicatePreservesItsIdentityAndPin() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    let original = store.insert(.text("keep me"))
    store.togglePin(id: original.id)
    store.insert(.text("other"))

    let promoted = store.insert(.text("keep me"))

    #expect(promoted.id == original.id)
    #expect(promoted.isPinned)
    #expect(store.items.count == 2)
}

// MARK: - Eviction

@Test @MainActor
func exceedingTheCapEvictsTheOldestUnpinnedItem() {
    let (store, dir) = makeStore(maxUnpinned: 3)
    defer { cleanup(dir) }

    for i in 1...5 { store.insert(.text("item \(i)")) }

    #expect(store.items.count == 3)
    #expect(store.items.map(\.textValue) == ["item 5", "item 4", "item 3"])
}

@Test @MainActor
func pinnedItemsSurviveEvictionAndDoNotCountTowardTheCap() {
    let (store, dir) = makeStore(maxUnpinned: 3)
    defer { cleanup(dir) }

    let pinned = store.insert(.text("pinned"))
    store.togglePin(id: pinned.id)

    for i in 1...10 { store.insert(.text("item \(i)")) }

    #expect(store.items.contains { $0.id == pinned.id })
    // 3 unpinned survivors plus the pinned one.
    #expect(store.items.count == 4)
    #expect(store.items.filter { !$0.isPinned }.count == 3)
}

@Test @MainActor
func unpinningAnItemMakesItEvictable() {
    let (store, dir) = makeStore(maxUnpinned: 2)
    defer { cleanup(dir) }

    let pinned = store.insert(.text("pinned"))
    store.togglePin(id: pinned.id)
    store.insert(.text("a"))
    store.insert(.text("b"))
    #expect(store.items.count == 3)

    // Now over the cap once it stops being pinned: it is the oldest, so it goes.
    store.togglePin(id: pinned.id)

    #expect(store.items.count == 2)
    #expect(!store.items.contains { $0.id == pinned.id })
}

// MARK: - Clearing

@Test @MainActor
func clearUnpinnedKeepsPinnedItemsButClearAllRemovesEverything() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    let pinned = store.insert(.text("pinned"))
    store.togglePin(id: pinned.id)
    store.insert(.text("transient"))

    store.clearUnpinned()
    #expect(store.items.count == 1)
    #expect(store.items[0].id == pinned.id)

    store.clearAll()
    #expect(store.items.isEmpty)
}

// MARK: - Text handling

@Test @MainActor
func veryLongTextIsTruncatedOnCapture() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    let huge = String(repeating: "x", count: ClipboardItem.maxTextLength + 5_000)
    let item = store.insert(.text(huge))

    #expect(item.textValue?.count == ClipboardItem.maxTextLength)
}

// MARK: - Persistence

@Test @MainActor
func historySurvivesARoundTripThroughDiskWithOrderAndPinsIntact() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    store.insert(.text("oldest"))
    let pinned = store.insert(.text("middle"))
    store.togglePin(id: pinned.id)
    store.insert(.text("newest"))
    store.saveNow()

    let reloaded = ClipboardStore(directory: dir, saveDebounce: .seconds(3600))
    reloaded.load()

    #expect(reloaded.items.map(\.textValue) == ["newest", "middle", "oldest"])
    #expect(reloaded.items[1].isPinned)
    #expect(reloaded.items[0].isPinned == false)
}

// MARK: - Images and blobs

@Test @MainActor
func insertingAnImageWritesABlobThatCanBeReadBack() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    let png = Data("not-really-a-png-but-unique".utf8)
    let item = store.insertImage(pngData: png, thumbnailData: nil, pixelWidth: 800, pixelHeight: 600)

    #expect(item.type == .image)
    #expect(item.pixelWidth == 800)
    #expect(store.imageData(for: item) == png)
    #expect(item.previewText == "Image 800 × 600")
}

@Test @MainActor
func theSameImageCopiedTwiceIsDedupedAndKeepsOneBlob() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    let png = Data("image-bytes".utf8)
    let first = store.insertImage(pngData: png, thumbnailData: nil, pixelWidth: 10, pixelHeight: 10)
    let second = store.insertImage(pngData: png, thumbnailData: nil, pixelWidth: 10, pixelHeight: 10)

    #expect(first.id == second.id)
    #expect(store.items.count == 1)

    let blobs = try? FileManager.default.contentsOfDirectory(
        at: dir.appendingPathComponent("Blobs"), includingPropertiesForKeys: nil
    )
    #expect(blobs?.count == 1)
}

@Test @MainActor
func savingCollectsBlobsLeftBehindByEvictedImages() {
    let (store, dir) = makeStore(maxUnpinned: 1)
    defer { cleanup(dir) }

    let evicted = store.insertImage(pngData: Data("first".utf8), thumbnailData: nil, pixelWidth: 1, pixelHeight: 1)
    let kept = store.insertImage(pngData: Data("second".utf8), thumbnailData: nil, pixelWidth: 1, pixelHeight: 1)
    #expect(store.items.count == 1)

    store.saveNow()

    let blobsDir = dir.appendingPathComponent("Blobs")
    let remaining = (try? FileManager.default.contentsOfDirectory(at: blobsDir, includingPropertiesForKeys: nil)) ?? []
    #expect(remaining.count == 1)
    #expect(remaining.first?.lastPathComponent == kept.imageFileName)
    #expect(store.imageData(for: evicted) == nil)
}

@Test @MainActor
func imagesWhoseBlobVanishedAreDroppedOnLoad() {
    let (store, dir) = makeStore()
    defer { cleanup(dir) }

    store.insert(.text("text survives"))
    let image = store.insertImage(pngData: Data("bytes".utf8), thumbnailData: nil, pixelWidth: 1, pixelHeight: 1)
    store.saveNow()

    // Simulate the blob being deleted out from under us.
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("Blobs/\(image.imageFileName!)"))

    let reloaded = ClipboardStore(directory: dir, saveDebounce: .seconds(3600))
    reloaded.load()

    #expect(reloaded.items.count == 1)
    #expect(reloaded.items[0].type == .text)
}
