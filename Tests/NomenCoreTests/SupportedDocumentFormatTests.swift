import Foundation
import Testing
@testable import NomenCore

@Test func knownExtensions() {
    #expect(SupportedDocumentFormat.isSupported(fileExtension: "PDF"))
    #expect(SupportedDocumentFormat.isSupported(fileExtension: "docx"))
    #expect(SupportedDocumentFormat.isSupported(fileExtension: "markdown"))
    #expect(!SupportedDocumentFormat.isSupported(fileExtension: "doc"))
    #expect(!SupportedDocumentFormat.isSupported(fileExtension: "jpg"))
}

@Test func urlUsesPathExtension() {
    let url = URL(fileURLWithPath: "/tmp/brief.rtf")
    #expect(SupportedDocumentFormat.isSupported(url: url))
}

@Test func openPanelIncludesPDF() {
    #expect(SupportedDocumentFormat.openPanelContentTypes.contains(.pdf))
}
