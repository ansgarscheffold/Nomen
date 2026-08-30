import Foundation
import os.log

/// Full outcome of one on-device model run (for UI + pipeline debug).
struct DocumentAnalysisPackage: Sendable {
    let result: DocumentUnderstandingResult
    let modelRawReply: String?
    let jsonSuggestedTitle: String?
    let jsonDocumentDateISO: String?
    let jsonDateFromDocument: Bool?
    /// Human-readable failure (model off, JSON parse, etc.).
    let errorStep: String?
    let usedFilenameFallbackForTitle: Bool
}

extension DocumentAnalysisPackage {
    static func filenameFallback(
        fallbackFilenameStem: String,
        fileModificationDate: Date,
        errorStep: String?,
        modelRawReply: String? = nil
    ) -> DocumentAnalysisPackage {
        DocumentAnalysisPackage(
            result: OnDeviceDocumentAnalyzer.fallbackWithoutModel(
                fallbackFilenameStem: fallbackFilenameStem,
                fileModificationDate: fileModificationDate
            ),
            modelRawReply: modelRawReply,
            jsonSuggestedTitle: nil,
            jsonDocumentDateISO: nil,
            jsonDateFromDocument: nil,
            errorStep: errorStep,
            usedFilenameFallbackForTitle: true
        )
    }

    static func titledFallback(
        title: String,
        fileModificationDate: Date,
        errorStep: String?,
        modelRawReply: String? = nil
    ) -> DocumentAnalysisPackage {
        DocumentAnalysisPackage(
            result: DocumentUnderstandingResult(
                title: title,
                documentDate: fileModificationDate,
                usedContentDate: false
            ),
            modelRawReply: modelRawReply,
            jsonSuggestedTitle: nil,
            jsonDocumentDateISO: nil,
            jsonDateFromDocument: nil,
            errorStep: errorStep,
            usedFilenameFallbackForTitle: true
        )
    }
}

enum DocumentAnalysisError: LocalizedError {
    case foundationModelsSDKMissing
    case requiresMacOS26
    case modelUnavailable(String)
    case generationFailed(String)
    case ggufModelFileMissing

    var errorDescription: String? {
        switch self {
        case .foundationModelsSDKMissing:
            return "Foundation Models framework not present in this SDK build."
        case .requiresMacOS26:
            return "Requires macOS 26 with Apple Intelligence."
        case .modelUnavailable(let reason):
            return "On-device model unavailable: \(reason)"
        case .generationFailed(let message):
            return "Model generation failed: \(message)"
        case .ggufModelFileMissing:
            return "GGUF model files are not downloaded (Settings → download Qwen2.5-7B GGUF)."
        }
    }
}

enum OnDeviceDocumentAnalyzer {
    private static let log = Logger(subsystem: NomenLog.subsystem, category: "analysis")

    /// Always returns a usable `result`; errors are described in `errorStep` and raw model text in `modelRawReply` when present.
    static func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode,
        inferenceBackend: NamingInferenceBackend
    ) async -> DocumentAnalysisPackage {
        if inferenceBackend == .llamaQwenGGUF {
            log.debug("analyzePackage (Qwen GGUF) excerpt length=\(sampleText.count, privacy: .public)")
            return await DocumentLlamaNaming.analyzePackage(
                sampleText: sampleText,
                fileModificationDate: fileModificationDate,
                fallbackFilenameStem: fallbackFilenameStem,
                localeIdentifier: localeIdentifier,
                outputLanguageMode: outputLanguageMode
            )
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            log.debug("analyzePackage (Foundation) excerpt length=\(sampleText.count, privacy: .public)")
            return await DocumentAINaming.analyzePackage(
                sampleText: sampleText,
                fileModificationDate: fileModificationDate,
                fallbackFilenameStem: fallbackFilenameStem,
                localeIdentifier: localeIdentifier,
                outputLanguageMode: outputLanguageMode
            )
        }
        return DocumentAnalysisPackage.filenameFallback(
            fallbackFilenameStem: fallbackFilenameStem,
            fileModificationDate: fileModificationDate,
            errorStep: String(describing: DocumentAnalysisError.requiresMacOS26)
        )
        #else
        return DocumentAnalysisPackage.filenameFallback(
            fallbackFilenameStem: fallbackFilenameStem,
            fileModificationDate: fileModificationDate,
            errorStep: String(describing: DocumentAnalysisError.foundationModelsSDKMissing)
        )
        #endif
    }

    static func fallbackWithoutModel(
        fallbackFilenameStem: String,
        fileModificationDate: Date
    ) -> DocumentUnderstandingResult {
        let title = FilenameSanitizer.archiveFallbackTitle(fromFilenameStem: fallbackFilenameStem)
        return DocumentUnderstandingResult(
            title: title,
            documentDate: fileModificationDate,
            usedContentDate: false
        )
    }
}
