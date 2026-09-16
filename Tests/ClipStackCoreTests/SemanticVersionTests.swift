import Testing
@testable import ClipStackCore

@Test
func versionsCompareNumericallyNotAsStrings() {
    // The classic update-check bug: "1.10.0" < "1.9.0" by string ordering.
    #expect(SemanticVersion("1.9.0")! < SemanticVersion("1.10.0")!)
    #expect(SemanticVersion("1.2.0")! < SemanticVersion("1.2.1")!)
    #expect(SemanticVersion("2.0.0")! > SemanticVersion("1.99.99")!)
}

@Test
func theGitHubTagPrefixIsIgnored() {
    #expect(SemanticVersion("v1.2.3")! == SemanticVersion("1.2.3")!)
    #expect(SemanticVersion("V1.2.3")! == SemanticVersion("1.2.3")!)
    #expect(SemanticVersion("v1.0.0")! > SemanticVersion("0.9.9")!)
}

@Test
func missingTrailingComponentsReadAsZero() {
    #expect(SemanticVersion("1.2")! == SemanticVersion("1.2.0")!)
    #expect(SemanticVersion("1")! == SemanticVersion("1.0.0")!)
    #expect(SemanticVersion("1.2")! < SemanticVersion("1.2.1")!)
}

@Test
func prereleaseSuffixesAreIgnoredRatherThanRejected() {
    #expect(SemanticVersion("1.2.0-beta.1")! == SemanticVersion("1.2.0")!)
    #expect(SemanticVersion("v2.0.0-rc1")! > SemanticVersion("1.9.0")!)
}

@Test
func anEqualVersionIsNotAnUpdate() {
    let running = SemanticVersion("1.0.0")!
    let published = SemanticVersion("v1.0.0")!
    #expect(!(published > running))
}

@Test
func garbageTagsAreRejectedRatherThanTreatedAsZero() {
    // A nil here makes UpdateChecker skip silently, which is the safe outcome:
    // treating an unparseable tag as 0.0.0 would suppress real updates forever.
    #expect(SemanticVersion("") == nil)
    #expect(SemanticVersion("nightly") == nil)
    #expect(SemanticVersion("v") == nil)
}
