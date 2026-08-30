import AppKit
import Foundation
import PDFKit
import ZIPFoundation
import NomenCore

enum ExtractionError: LocalizedError {
    case unsupportedType(String)
    case couldNotOpen
    case encoding
    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext):
            return "Dateityp .\(ext) wird nicht unterstützt."
        case .couldNotOpen:
            return "Die Datei konnte nicht geöffnet werden."
        case .encoding:
            return "Die Datei konnte nicht als Text gelesen werden."
        }
    }
}

enum DocumentTextExtractor {
    private static let maxBytes = 512_000
    private static let docxTextRunRegex = try! NSRegularExpression(
        pattern: #"<w:t[^>]*>(.*?)</w:t>"#,
        options: [.dotMatchesLineSeparators]
    )

    static func extractText(from url: URL) throws -> String {
        switch SupportedDocumentFormat(rawValue: url.pathExtension.lowercased()) {
        case .pdf:
            return try extractPDF(url)
        case .txt, .md, .markdown, .csv, .log:
            return try extractPlain(url)
        case .rtf, .rtfd:
            return try extractRTF(url)
        case .docx:
            return try extractDOCX(url)
        case nil:
            throw ExtractionError.unsupportedType(url.pathExtension.lowercased())
        }
    }

    /// Raw text from the PDF’s embedded string layer.
    /// - Parameter maxPages: Maximum number of pages to read (default: all pages up to 40).
    static func embeddedPDFText(from url: URL, maxPages: Int = 40) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw ExtractionError.couldNotOpen
        }
        return embeddedPDFText(from: doc, maxPages: maxPages)
    }

    static func embeddedPDFText(from document: PDFDocument, maxPages: Int = 40) -> String {
        extractPDF(document, maxPages: maxPages)
    }

    private static func extractPDF(_ url: URL, maxPages: Int = 40) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw ExtractionError.couldNotOpen
        }
        let joined = extractPDF(doc, maxPages: maxPages)
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return joined
    }

    private static func extractPDF(_ document: PDFDocument, maxPages: Int) -> String {
        var parts: [String] = []
        let limit = min(document.pageCount, maxPages)
        parts.reserveCapacity(limit)
        for i in 0 ..< limit {
            guard let page = document.page(at: i), let s = page.string, !s.isEmpty else { continue }
            parts.append(s)
        }
        let joined = parts.joined(separator: "\n")
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return trim(joined)
    }

    private static func extractPlain(_ url: URL) throws -> String {
        let data = try cappedData(url)
        guard let s = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ExtractionError.encoding
        }
        return trim(s)
    }

    private static func extractRTF(_ url: URL) throws -> String {
        let data = try cappedData(url)
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            throw ExtractionError.couldNotOpen
        }
        return trim(attributed.string)
    }

    private static func extractDOCX(_ url: URL) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ExtractionError.couldNotOpen
        }
        guard let entry = archive["word/document.xml"] else {
            throw ExtractionError.couldNotOpen
        }
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            data.append(chunk)
        })
        guard let xml = String(data: data, encoding: .utf8) else {
            throw ExtractionError.encoding
        }
        return trim(xmlDocxPlainText(from: xml))
    }

    private static func xmlDocxPlainText(from xml: String) -> String {
        let ns = xml as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = docxTextRunRegex.matches(in: xml, options: [], range: full)
        var parts: [String] = []
        parts.reserveCapacity(min(matches.count, 512))
        var total = 0
        for m in matches where m.numberOfRanges > 1 {
            let r = m.range(at: 1)
            guard let range = Range(r, in: xml) else { continue }
            let piece = String(xml[range])
            parts.append(piece)
            total += piece.count + 1
            if total >= 8_000 { break }
        }
        return parts.joined(separator: " ")
    }

    private static func cappedData(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maxBytes) ?? Data()
    }

    private static func trim(_ s: String) -> String {
        // 8 000 chars is enough for naming — typically covers 2–4 dense pages.
        // Keeping this low avoids flooding callers that feed the text to an on-device model.
        let clipped = String(s.prefix(8_000))
        return clipped
    }
}
