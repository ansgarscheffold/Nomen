import Foundation
import NomenCore

/// Baut Vorschauzeilen und Debug-Snapshots aus einem abgeschlossenen Analyse-Lauf.
/// Der Batch-Loop (Fortschritt, Abbruch) bleibt im ViewModel.
enum DocumentFileAnalyzer {
    static func makeCompletedRow(
        url: URL,
        originalName: String,
        extension ext: String,
        schema: DateNameSchema,
        snap: DocumentAIProcessor.ExtractionSnapshot,
        fileModificationDate: Date,
        package: DocumentAnalysisPackage,
        strings: L10n,
        includePipelineDebug: Bool
    ) -> RenamePreviewRow {
        let understanding = package.result
        let proposedBase = FilenameFormatting.formatFilename(
            schema: schema,
            title: understanding.title,
            date: understanding.documentDate ?? fileModificationDate,
            originalExtension: ext
        )
        let unique = FileRenameOperations.uniquifyFilename(
            desiredName: proposedBase,
            directory: url.deletingLastPathComponent(),
            ignoreIfSameAs: url
        )

        var dateHint = understanding.usedContentDate ? strings.dateFromContent : strings.dateFromFile
        if let hintSuffix = package.errorStep.map({ strings.modelFallbackUserMessage(detail: $0) }) {
            dateHint = "\(dateHint) — \(hintSuffix)"
        }

        let pipelineDebug: PipelineDebugSnapshot? = includePipelineDebug
            ? makePipelineDebug(
                ext: ext,
                sample: snap.combinedText,
                embeddedPDFCount: snap.embeddedCharacterCount,
                ocrCount: snap.ocrCharacterCount > 0 ? snap.ocrCharacterCount : nil,
                usedVisionOCRForSample: snap.usedVisionOCRAsPrimary,
                package: package,
                understanding: understanding
            )
            : nil

        return RenamePreviewRow(
            id: UUID(),
            sourceURL: url,
            originalName: originalName,
            proposedName: unique,
            statusMessage: dateHint,
            usedFallbackDate: !understanding.usedContentDate,
            namingBasis: understanding,
            pipelineDebug: pipelineDebug,
            isAnalysisPlaceholder: false
        )
    }

    static func makeFailedRow(url: URL, originalName: String, message: String) -> RenamePreviewRow {
        RenamePreviewRow(
            id: UUID(),
            sourceURL: url,
            originalName: originalName,
            proposedName: originalName,
            statusMessage: message,
            usedFallbackDate: true,
            namingBasis: nil,
            pipelineDebug: nil,
            isAnalysisPlaceholder: false
        )
    }

    static func makePipelineDebug(
        ext: String,
        sample: String,
        embeddedPDFCount: Int?,
        ocrCount: Int?,
        usedVisionOCRForSample: Bool,
        package: DocumentAnalysisPackage,
        understanding: DocumentUnderstandingResult
    ) -> PipelineDebugSnapshot {
        let excerpt = String(sample.prefix(14_000))
        let rawCap = 8000
        let chosenLabel: String
        let summary: String
        if ext.lowercased() == SupportedDocumentFormat.pdf.rawValue {
            if usedVisionOCRForSample {
                let ec = embeddedPDFCount.map { "\($0) chars" } ?? "n/a"
                let oc = ocrCount.map { "\($0) chars" } ?? "n/a"
                summary = "PDF · embedded probe: \(ec) · Vision OCR (page 1): \(oc) · sample: \(sample.count) chars"
                chosenLabel = "Vision OCR (page 1)"
            } else {
                let ec = embeddedPDFCount.map { "\($0) chars" } ?? "n/a"
                summary = "PDF · embedded text: \(ec) (up to 2 pages) · sample: \(sample.count) chars"
                chosenLabel = "Embedded PDF text"
            }
        } else {
            summary = "Non-PDF · extracted text: \(sample.count) characters"
            chosenLabel = "File contents"
        }
        return PipelineDebugSnapshot(
            extractionSummary: summary,
            embeddedPDFCharacterCount: embeddedPDFCount,
            ocrCharacterCount: ocrCount,
            chosenSourceLabel: chosenLabel,
            textSampleForModel: excerpt,
            textTotalCharacters: excerpt.count,
            modelRawReply: package.modelRawReply.map { String($0.prefix(rawCap)) },
            jsonSuggestedTitle: package.jsonSuggestedTitle,
            jsonDocumentDateISO: package.jsonDocumentDateISO,
            jsonDateFromDocument: package.jsonDateFromDocument,
            modelOrParseError: package.errorStep,
            finalTitleAfterSanitize: understanding.title,
            usedContentDate: understanding.usedContentDate,
            usedFilenameFallbackForTitle: package.usedFilenameFallbackForTitle
        )
    }
}
