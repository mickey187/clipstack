import Foundation
import Testing
@testable import ClipStackCore

@Test
func sizesGrowStrictlyFromSmallToLarge() {
    let steps = PanelSize.allCases
    #expect(steps == [.small, .medium, .large])

    for (smaller, larger) in zip(steps, steps.dropFirst()) {
        #expect(smaller.width < larger.width)
        #expect(smaller.height < larger.height)
        #expect(smaller.scaled(12) < larger.scaled(12))
    }
}

@Test
func smallIsThePreSettingBaseline() {
    #expect(PanelSize.small.width == 340)
    #expect(PanelSize.small.height == 440)
    #expect(PanelSize.small.scaled(12) == 12)
}

@Test
func scaledPointsAreWholeNumbers() {
    for size in PanelSize.allCases {
        for points in stride(from: CGFloat(1), through: 30, by: 1) {
            let scaled = size.scaled(points)
            #expect(scaled == scaled.rounded())
            #expect(scaled >= points)
        }
        #expect(size.width == size.width.rounded())
        #expect(size.height == size.height.rounded())
    }
}

/// The raw values are what lands in `UserDefaults`, so renaming one silently
/// resets everybody's choice.
@Test
func rawValuesAreStable() {
    #expect(PanelSize(rawValue: "small") == .small)
    #expect(PanelSize(rawValue: "medium") == .medium)
    #expect(PanelSize(rawValue: "large") == .large)
    #expect(PanelSize(rawValue: "huge") == nil)
}
