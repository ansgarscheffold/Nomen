import AppKit
import Foundation
import PDFKit
import Vision
import NomenCore

enum DocumentAIProcessorError: LocalizedError {
    case ocrFailed

    var errorDescription: String? {
        switch self {
        case .ocrFailed:
            return "PDF konnte nicht für OCR geöffnet werden oder es fehlt eine lesbare Seite."
        }
    }
}

// MARK: - Texterkennung (Vision + PDFKit)

/// PDF: eingebetteter Text bzw. Vision-OCR auf den ersten Seiten (Briefkopf, Typ, Datum, Aussteller).
enum DocumentAIProcessor {
    private static let thumbnailSize = NSSize(width: 1536, height: 1536)
    /// Deckblatt/Anschreiben oft auf S. 1; Rechnung, Aktenzeichen, Datum häufig erst auf S. 2–3.
    private static let maxNamingPages = 3
    private static let embeddedTextEnough = 300

    struct ExtractionSnapshot: Sendable {
        var combinedText: String
        var embeddedCharacterCount: Int?
        var ocrCharacterCount: Int
        var ocrPageCount: Int
        var usedVisionOCRAsPrimary: Bool
    }

    static func extractForRenaming(url: URL, extLowercased: String) async throws -> ExtractionSnapshot {
        let limit = DocumentNamingPromptBuilder.excerptCharacterLimit
        if extLowercased == SupportedDocumentFormat.pdf.rawValue {
            guard let pdf = PDFDocument(url: url) else {
                throw DocumentAIProcessorError.ocrFailed
            }
            let embedded = DocumentTextExtractor.embeddedPDFText(from: pdf, maxPages: maxNamingPages)
            let embeddedCount = embedded.trimmingCharacters(in: .whitespacesAndNewlines).count

            if embeddedCount > embeddedTextEnough {
                return ExtractionSnapshot(
                    combinedText: String(embedded.prefix(limit)),
                    embeddedCharacterCount: embeddedCount,
                    ocrCharacterCount: 0,
                    ocrPageCount: 0,
                    usedVisionOCRAsPrimary: false
                )
            }

            // Scanned/image PDF — OCR der ersten Seiten (nicht nur S. 1: Infos sitzen oft weiter hinten).
            let (ocrRaw, pagesRead) = try await recognizeTextOnPDFPages(pdf, maxPages: maxNamingPages)
            let ocrCount = ocrRaw.trimmingCharacters(in: .whitespacesAndNewlines).count
            let combined = ocrRaw.isEmpty ? embedded : ocrRaw
            return ExtractionSnapshot(
                combinedText: String(combined.prefix(limit)),
                embeddedCharacterCount: embeddedCount,
                ocrCharacterCount: ocrCount,
                ocrPageCount: pagesRead,
                usedVisionOCRAsPrimary: true
            )
        }
        let raw = try DocumentTextExtractor.extractText(from: url)
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExtractionSnapshot(
            combinedText: String(raw.prefix(limit)),
            embeddedCharacterCount: t.count,
            ocrCharacterCount: 0,
            ocrPageCount: 0,
            usedVisionOCRAsPrimary: false
        )
    }

    private static func recognizeTextOnPDFPages(
        _ pdf: PDFDocument,
        maxPages: Int
    ) async throws -> (text: String, pagesRead: Int) {
        let limit = min(pdf.pageCount, maxPages)
        guard limit > 0, pdf.page(at: 0) != nil else {
            throw DocumentAIProcessorError.ocrFailed
        }
        var parts: [String] = []
        parts.reserveCapacity(limit)
        var pagesRead = 0
        for i in 0 ..< limit {
            if Task.isCancelled { break }
            guard let page = pdf.page(at: i) else { continue }
            let pageText = (try? await recognizeTextOnPDFPage(page)) ?? ""
            pagesRead += 1
            if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(pageText)
            }
        }
        return (parts.joined(separator: "\n"), pagesRead)
    }

    private static func recognizeTextOnPDFPage(_ page: PDFPage) async throws -> String {
        guard let cgImage = renderPageThumbnail(page) else {
            throw DocumentAIProcessorError.ocrFailed
        }
        return try await recognizeTextOnImage(cgImage)
    }

    private static func renderPageThumbnail(_ page: PDFPage) -> CGImage? {
        let nsImage = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func recognizeTextOnImage(_ cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                let sorted = observations.sorted { a, b in
                    let ra = a.boundingBox
                    let rb = b.boundingBox
                    let dy = ra.midY - rb.midY
                    if abs(dy) > 0.015 {
                        return dy > 0
                    }
                    return ra.minX < rb.minX
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
