import Testing
@testable import NomenCore

@Test func slugKeepsUmlautsAndEszett() {
    #expect(FilenameSanitizer.slugTitle("Überweisung Straße") == "Überweisung Straße")
}

@Test func slugCollapsesPunctuationToSpaces() {
    #expect(FilenameSanitizer.slugTitle("Rechnung — iPhone_2024") == "Rechnung iPhone 2024")
}

@Test func cleanStemStripsISODatePrefix() {
    #expect(FilenameSanitizer.cleanStemForTitle("2026 04 10 01 33 Doc") == "Doc")
}

@Test func cleanStemStripsCompactYMD() {
    #expect(FilenameSanitizer.cleanStemForTitle("231215 Hausratversicherung") == "Hausratversicherung")
}

@Test func cleanStemDropsDigitOnlyTokens() {
    let cleaned = FilenameSanitizer.cleanStemForTitle("Apple Support Case 102866598713 11_4_2026_1_24pm")
    #expect(cleaned.contains("Apple Support Case"))
    #expect(!cleaned.contains("102866598713"))
}

@Test func archiveFallbackUsesDocumentWhenEmpty() {
    #expect(FilenameSanitizer.archiveFallbackTitle(fromFilenameStem: "---") == "Document")
    #expect(FilenameSanitizer.archiveFallbackTitle(fromFilenameStem: "Rechnung") == "Rechnung")
}
