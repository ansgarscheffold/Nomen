import AppKit
import Foundation
import os.log
import PDFKit
import Vision

enum DocumentAIProcessorError: LocalizedError {
    case ocrFailed

    var errorDescription: String? {
        switch self {
        case .ocrFailed:
            return "PDF konnte nicht für OCR geöffnet werden oder die erste Seite fehlt."
        }
    }
}

// MARK: - Texterkennung (Vision + PDFKit)

/// Orchestriert **PDF-OCR** nur auf der **ersten Seite** (Thumbnail ~2000 px); sonst Textimport.
enum DocumentAIProcessor {
    private static let thumbnailSize = NSSize(width: 2000, height: 2000)

    struct ExtractionSnapshot: Sendable {
        var combinedText: String
        var embeddedCharacterCount: Int?
        var ocrCharacterCount: Int
        var usedVisionOCRAsPrimary: Bool
    }

    static func extractForRenaming(url: URL, extLowercased: String) async throws -> ExtractionSnapshot {
        if extLowercased == SupportedDocumentFormat.pdf.rawValue {
            // For naming purposes, first 2 pages always contain the key info (letterhead,
            // document type, date, issuer). Reading 40 pages produces unnecessary noise and
            // can overwhelm the on-device model with boilerplate from page 3+.
            let embedded = (try? DocumentTextExtractor.embeddedPDFText(from: url, maxPages: 2)) ?? ""
            let embeddedCount = embedded.trimmingCharacters(in: .whitespacesAndNewlines).count

            if embeddedCount > 300 {
                return ExtractionSnapshot(
                    combinedText: embedded,
                    embeddedCharacterCount: embeddedCount,
                    ocrCharacterCount: 0,
                    usedVisionOCRAsPrimary: false
                )
            }

            // Scanned/image PDF — fall back to Vision OCR on the first page
            let ocrRaw = try await performFirstPageOCR(at: url)
            let ocrCount = ocrRaw.trimmingCharacters(in: .whitespacesAndNewlines).count
            return ExtractionSnapshot(
                combinedText: ocrRaw.isEmpty ? embedded : ocrRaw,
                embeddedCharacterCount: embeddedCount,
                ocrCharacterCount: ocrCount,
                usedVisionOCRAsPrimary: true
            )
        }
        let raw = try DocumentTextExtractor.extractText(from: url)
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExtractionSnapshot(
            combinedText: raw,
            embeddedCharacterCount: t.count,
            ocrCharacterCount: 0,
            usedVisionOCRAsPrimary: false
        )
    }

    private static func performFirstPageOCR(at url: URL) async throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw DocumentAIProcessorError.ocrFailed
        }
        guard let page0 = pdf.page(at: 0) else {
            throw DocumentAIProcessorError.ocrFailed
        }
        return try await recognizeTextOnPDFPage(page0)
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

// MARK: - On-Device-Sprachmodell (FoundationModels)

#if canImport(FoundationModels)
import FoundationModels

// Hinweis: Im Xcode-Code-Along nutzt Apple `@Generable` + `respond(to:generating:)`.
// Dafür muss das Compiler-Plugin `FoundationModelsMacros` aktiv sein (Xcode-Build).
// `swift build` auf der Kommandozeile liefert oft kein Makro-Plugin — daher JSON-Pfad unten.

@available(macOS 26.0, *)
enum DocumentAINaming {
    private static let log = Logger(subsystem: NomenLog.subsystem, category: "DocumentAINaming")

    /// Erzwingt für die Session-Anweisungen nur `en_US` oder `de_DE` (laut `supportsLocale`),
    /// damit das On-Device-Modell nicht mit abweichenden Locales abbricht.
    private static func modelInstructionLocaleIdentifier(uiLocaleIdentifier: String) -> String {
        let enUS = Locale(identifier: "en_US")
        let deDE = Locale(identifier: "de_DE")
        let germanUI = uiLocaleIdentifier.hasPrefix("de")
        if germanUI {
            if SystemLanguageModel.default.supportsLocale(deDE) { return "de_DE" }
            if SystemLanguageModel.default.supportsLocale(enUS) { return "en_US" }
        } else {
            if SystemLanguageModel.default.supportsLocale(enUS) { return "en_US" }
            if SystemLanguageModel.default.supportsLocale(deDE) { return "de_DE" }
        }
        return "en_US"
    }

    static func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode
    ) async -> DocumentAnalysisPackage {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            let desc = String(describing: reason)
            log.error("SystemLanguageModel unavailable: \(desc, privacy: .public)")
            return DocumentAnalysisPackage.filenameFallback(
                fallbackFilenameStem: fallbackFilenameStem,
                fileModificationDate: fileModificationDate,
                errorStep: desc
            )
        }

        let modelLocaleId = modelInstructionLocaleIdentifier(uiLocaleIdentifier: localeIdentifier)
        let (instructions, prompt, fallbackTitle) = DocumentNamingPipeline.prompts(
            sampleText: sampleText,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            modelLocaleId: modelLocaleId,
            outputLanguageMode: outputLanguageMode,
            uiLocaleIdentifier: localeIdentifier
        )

        let session = LanguageModelSession(model: model, instructions: instructions)

        do {
            // Wir definieren die Optionen explizit
            var options = GenerationOptions()
            options.temperature = 0.0 // Erzwingt Sachlichkeit

            // Wenn topK nicht existiert, nutzt das Modell bei temperature 0.0 
            // automatisch den wahrscheinlichsten Pfad.
            // Falls das Framework es unterstützt (Apple Intelligence SDK Stand 2026):
            // options.presencePenalty = 1.0 // Verhindert, dass er sich an OCR-Wörtern "festbeißt"

            let response = try await session.respond(
                to: prompt,
                options: options
            )
            let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            log.debug("Raw model reply length=\(raw.count, privacy: .public)")
            return DocumentNamingPipeline.analysisPackageFromRawReply(
                raw: raw,
                fileModificationDate: fileModificationDate,
                fallbackFilenameStem: fallbackFilenameStem,
                fallbackTitle: fallbackTitle
            )
        } catch {
            log.error("Model call failed: \(String(describing: error), privacy: .public)")
            return DocumentAnalysisPackage.titledFallback(
                title: fallbackTitle,
                fileModificationDate: fileModificationDate,
                errorStep: error.localizedDescription
            )
        }
    }
}
#endif
