import Foundation
import Testing
@testable import NomenCore

private func fileDate() -> Date {
    var comps = DateComponents()
    comps.year = 2024
    comps.month = 1
    comps.day = 15
    return Calendar(identifier: .gregorian).date(from: comps)!
}

@Test func parsesValidJSON() {
    let raw = """
    {"date":"2023-12-01","archiveTitle":"Stromrechnung 2023 E.ON"}
    """
    let pkg = DocumentNamingPipeline.analysisPackageFromRawReply(
        raw: raw,
        fileModificationDate: fileDate(),
        fallbackFilenameStem: "scan",
        fallbackTitle: "scan"
    )
    #expect(pkg.result.title == "Stromrechnung 2023 E.ON")
    #expect(pkg.jsonDocumentDateISO == "2023-12-01")
    #expect(pkg.jsonSuggestedTitle == "Stromrechnung 2023 E.ON")
    #expect(pkg.result.usedContentDate)
    #expect(!pkg.usedFilenameFallbackForTitle)
    #expect(pkg.errorStep == nil)
}

@Test func acceptsAlternateTitleKeys() {
    let raw = #"{"documentDate":"2024-02-15","suggested_title":"Steuerbescheid 2024 Finanzamt"}"#
    let pkg = DocumentNamingPipeline.analysisPackageFromRawReply(
        raw: raw,
        fileModificationDate: fileDate(),
        fallbackFilenameStem: "x",
        fallbackTitle: "x"
    )
    #expect(pkg.result.title == "Steuerbescheid 2024 Finanzamt")
    #expect(pkg.result.usedContentDate)
}

@Test func invalidJSONUsesFallbackTitle() {
    let pkg = DocumentNamingPipeline.analysisPackageFromRawReply(
        raw: "not json at all",
        fileModificationDate: fileDate(),
        fallbackFilenameStem: "Rechnung",
        fallbackTitle: "Rechnung"
    )
    #expect(pkg.result.title == "Rechnung")
    #expect(!pkg.result.usedContentDate)
    #expect(pkg.usedFilenameFallbackForTitle)
    #expect(pkg.errorStep != nil)
}

@Test func wallOfTextFallsBack() {
    let long = Array(repeating: "Wort", count: 50).joined(separator: " ")
    let raw = #"{"date":"2023-12-01","archiveTitle":"\#(long)"}"#
    let pkg = DocumentNamingPipeline.analysisPackageFromRawReply(
        raw: raw,
        fileModificationDate: fileDate(),
        fallbackFilenameStem: "Doc",
        fallbackTitle: "Doc"
    )
    #expect(pkg.result.title == "Doc")
    #expect(pkg.usedFilenameFallbackForTitle)
}

@Test func weakGenericTitleFallsBack() {
    let raw = #"{"date":"2023-12-01","archiveTitle":"scan"}"#
    let pkg = DocumentNamingPipeline.analysisPackageFromRawReply(
        raw: raw,
        fileModificationDate: fileDate(),
        fallbackFilenameStem: "Rechnung",
        fallbackTitle: "Rechnung"
    )
    #expect(pkg.result.title == "Rechnung")
    #expect(pkg.usedFilenameFallbackForTitle)
}

@Test func validatedDateAcceptsISOHead() {
    let (date, fromDoc) = DocumentNamingPipeline.validatedDocumentDate(
        iso: "2022-06-03T12:00:00Z",
        fileModificationDate: fileDate()
    )
    #expect(fromDoc)
    let y = Calendar(identifier: .gregorian).component(.year, from: date)
    #expect(y == 2022)
}

@Test func validatedDateRejectsOutOfRangeYear() {
    let (_, fromDoc) = DocumentNamingPipeline.validatedDocumentDate(
        iso: "1980-01-01",
        fileModificationDate: fileDate()
    )
    #expect(!fromDoc)
}

@Test func truncateToFirstBalancedJSONObject() {
    let raw = #"prefix {"date":"2023-01-01","archiveTitle":"X"} trailing { "no": true }"#
    let cut = DocumentNamingPipeline.truncateToFirstBalancedJSONObject(raw)
    #expect(cut == #"{"date":"2023-01-01","archiveTitle":"X"}"#)
}

@Test func ggufStopWhenJSONComplete() {
    #expect(
        DocumentNamingPipeline.ggufShouldStopGeneration(
            leadIn: #"{"date":""#,
            generatedSuffix: #"2023-01-01","archiveTitle":"Rechnung"}"#
        )
    )
    #expect(
        !DocumentNamingPipeline.ggufShouldStopGeneration(
            leadIn: #"{"date":""#,
            generatedSuffix: "2023-01-01"
        )
    )
}

@Test func isWeakGenericTitle() {
    #expect(DocumentNamingPipeline.isWeakGenericTitle("PDF"))
    #expect(DocumentNamingPipeline.isWeakGenericTitle("12 04"))
    #expect(!DocumentNamingPipeline.isWeakGenericTitle("Rechnung Strom"))
}

@Test func repairInvalidJSONEscapesKeepsValidPairs() {
    let repaired = DocumentNamingPipeline.repairInvalidJSONStringEscapes(
        #"{"archiveTitle":"Hallo"}"#
    )
    #expect(repaired.contains("Hallo"))
}
