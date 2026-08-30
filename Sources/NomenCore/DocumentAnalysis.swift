import Foundation

/// Full outcome of one on-device model run (for UI + pipeline debug).
public struct DocumentAnalysisPackage: Sendable {
    public let result: DocumentUnderstandingResult
    public let modelRawReply: String?
    public let jsonSuggestedTitle: String?
    public let jsonDocumentDateISO: String?
    public let jsonDateFromDocument: Bool?
    /// Human-readable failure (model off, JSON parse, etc.).
    public let errorStep: String?
    public let usedFilenameFallbackForTitle: Bool

    public init(
        result: DocumentUnderstandingResult,
        modelRawReply: String?,
        jsonSuggestedTitle: String?,
        jsonDocumentDateISO: String?,
        jsonDateFromDocument: Bool?,
        errorStep: String?,
        usedFilenameFallbackForTitle: Bool
    ) {
        self.result = result
        self.modelRawReply = modelRawReply
        self.jsonSuggestedTitle = jsonSuggestedTitle
        self.jsonDocumentDateISO = jsonDocumentDateISO
        self.jsonDateFromDocument = jsonDateFromDocument
        self.errorStep = errorStep
        self.usedFilenameFallbackForTitle = usedFilenameFallbackForTitle
    }
}

public extension DocumentAnalysisPackage {
    static func filenameFallback(
        fallbackFilenameStem: String,
        fileModificationDate: Date,
        errorStep: String?,
        modelRawReply: String? = nil
    ) -> DocumentAnalysisPackage {
        DocumentAnalysisPackage(
            result: DocumentUnderstandingResult.filenameFallback(
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

public enum DocumentAnalysisError: LocalizedError {
    case foundationModelsSDKMissing
    case requiresMacOS26
    case modelUnavailable(String)
    case generationFailed(String)
    case ggufModelFileMissing

    public var errorDescription: String? {
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
