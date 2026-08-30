import Foundation
import Testing
@testable import NomenCore

private func sampleDate() -> Date {
    var comps = DateComponents()
    comps.year = 2026
    comps.month = 4
    comps.day = 10
    return Calendar(identifier: .gregorian).date(from: comps)!
}

@Test func yearMonthTitle() {
    let name = FilenameFormatting.formatFilename(
        schema: .yearMonthTitle,
        title: "Rechnung iPhone",
        date: sampleDate(),
        originalExtension: "pdf"
    )
    #expect(name == "2026 04 Rechnung iPhone.pdf")
}

@Test func compactDateTitle() {
    let name = FilenameFormatting.formatFilename(
        schema: .compactDateTitle,
        title: "Rechnung iPhone",
        date: sampleDate(),
        originalExtension: "PDF"
    )
    #expect(name == "260410 Rechnung iPhone.pdf")
}

@Test func titleOnly() {
    let name = FilenameFormatting.formatFilename(
        schema: .titleOnly,
        title: "Rechnung iPhone",
        date: sampleDate(),
        originalExtension: "pdf"
    )
    #expect(name == "Rechnung iPhone.pdf")
}

@Test func stripsRedundantYearMonthPrefix() {
    let name = FilenameFormatting.formatFilename(
        schema: .yearMonthTitle,
        title: "2026 04 Rechnung",
        date: sampleDate(),
        originalExtension: "pdf"
    )
    #expect(name == "2026 04 Rechnung.pdf")
}

@Test func emptyTitleFallsBackToDocument() {
    let name = FilenameFormatting.formatFilename(
        schema: .titleOnly,
        title: "—",
        date: sampleDate(),
        originalExtension: ""
    )
    #expect(name == "Document")
}
