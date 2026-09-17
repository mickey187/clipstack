import Foundation
import Testing
@testable import ClipStackCore

private func image(_ seed: String) -> ClipboardItem {
    ClipboardItem(
        type: .image,
        imageFileName: "\(seed).png",
        pixelWidth: 800,
        pixelHeight: 600,
        contentHash: ClipboardItem.hash(of: seed)
    )
}

// MARK: - Link detection

@Test
func aBareURLIsALinkButProseAroundOneIsNot() {
    #expect(ClipboardItem.text("https://example.com/a?b=c").isLink)
    #expect(ClipboardItem.text("http://example.com").isLink)
    #expect(ClipboardItem.text("www.example.com").isLink)
    // Surrounding whitespace is a copy artefact, not content.
    #expect(ClipboardItem.text("  https://example.com\n").isLink)

    #expect(!ClipboardItem.text("see https://example.com for details").isLink)
    #expect(!ClipboardItem.text("just some text").isLink)
    #expect(!ClipboardItem.text("ftp://example.com").isLink)
    #expect(!ClipboardItem.text("https://").isLink)
    #expect(!image("shot").isLink)
}

// MARK: - Query matching

@Test
func matchingIsCaseAndAccentInsensitiveAndAnEmptyQueryMatchesEverything() {
    let item = ClipboardItem.text("Café Invoice 2026")

    #expect(item.matches(query: ""))
    #expect(item.matches(query: "   "))
    #expect(item.matches(query: "invoice"))
    #expect(item.matches(query: "CAFE"))
    #expect(item.matches(query: "ce 20"))
    #expect(!item.matches(query: "receipt"))
}

@Test
func imagesAreExcludedByAnyNonEmptyQuery() {
    let shot = image("shot")

    #expect(shot.matches(query: ""))
    #expect(!shot.matches(query: "image"))
    #expect(!shot.matches(query: "800"))
}

// MARK: - Category filtering

@Test
func theTextCategoryIncludesLinksWhileLinksIsTheURLSubset() {
    let items = [
        ClipboardItem.text("https://example.com"),
        ClipboardItem.text("plain text"),
        image("shot"),
    ]

    #expect(items.filtered(category: .all, query: "").count == 3)
    #expect(items.filtered(category: .text, query: "").map(\.textValue)
        == ["https://example.com", "plain text"])
    #expect(items.filtered(category: .link, query: "").map(\.textValue)
        == ["https://example.com"])
    #expect(items.filtered(category: .image, query: "").map(\.type) == [.image])
}

@Test
func categoryAndQueryComposeAndTheStoreOrderIsPreserved() {
    let items = [
        ClipboardItem.text("https://example.com/invoice"),
        ClipboardItem.text("invoice draft"),
        ClipboardItem.text("https://example.com/receipt"),
        image("shot"),
    ]

    #expect(items.filtered(category: .link, query: "invoice").map(\.textValue)
        == ["https://example.com/invoice"])
    #expect(items.filtered(category: .text, query: "example").map(\.textValue)
        == ["https://example.com/invoice", "https://example.com/receipt"])
    #expect(items.filtered(category: .image, query: "invoice").isEmpty)
}
