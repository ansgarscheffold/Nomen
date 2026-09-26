import Foundation

/// Öffentliche Facade: Prompt-Bau, JSON-Auswertung und Datumsvalidierung für beide Naming-Backends.
/// Implementierung liegt in PromptBuilder / ReplyParser / DateValidation.
public enum DocumentNamingPipeline {
    public static let modelTitleWallOfTextWordLimit = DocumentNamingReplyParser.modelTitleWallOfTextWordLimit
    public static let modelTitleWallOfTextCharLimit = DocumentNamingReplyParser.modelTitleWallOfTextCharLimit
    public static let excerptCharacterLimit = DocumentNamingPromptBuilder.excerptCharacterLimit
    public static let qwenAssistantJSONDatePrefill = DocumentNamingPromptBuilder.qwenAssistantJSONDatePrefill

    public static func formattedPromptDate(_ date: Date) -> String {
        DocumentNamingPromptBuilder.formattedPromptDate(date)
    }

    public static func prompts(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        modelLocaleId: String,
        outputLanguageMode: OutputLanguageMode,
        uiLocaleIdentifier: String
    ) -> (instructions: String, userPrompt: String, fallbackTitle: String) {
        DocumentNamingPromptBuilder.prompts(
            sampleText: sampleText,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            modelLocaleId: modelLocaleId,
            outputLanguageMode: outputLanguageMode,
            uiLocaleIdentifier: uiLocaleIdentifier
        )
    }

    public static func buildInstructions(
        modelLocaleId: String,
        outputLanguageMode: OutputLanguageMode,
        uiLocaleIdentifier: String
    ) -> String {
        DocumentNamingPromptBuilder.buildInstructions(
            modelLocaleId: modelLocaleId,
            outputLanguageMode: outputLanguageMode,
            uiLocaleIdentifier: uiLocaleIdentifier
        )
    }

    public static func instructionLocaleIdForLlamaInference(uiLocaleIdentifier: String) -> String {
        DocumentNamingPromptBuilder.instructionLocaleIdForLlamaInference(uiLocaleIdentifier: uiLocaleIdentifier)
    }

    public static func truncateToFirstBalancedJSONObject(_ raw: String) -> String {
        DocumentNamingReplyParser.truncateToFirstBalancedJSONObject(raw)
    }

    public static func ggufShouldStopGeneration(leadIn: String, generatedSuffix: String) -> Bool {
        DocumentNamingReplyParser.ggufShouldStopGeneration(leadIn: leadIn, generatedSuffix: generatedSuffix)
    }

    public static func buildUserPrompt(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        excerptCharacterLimit: Int = 3000
    ) -> String {
        DocumentNamingPromptBuilder.buildUserPrompt(
            sampleText: sampleText,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            excerptCharacterLimit: excerptCharacterLimit
        )
    }

    public static func sanitizeUntrustedPromptText(_ raw: String) -> String {
        DocumentNamingPromptBuilder.sanitizeUntrustedPromptText(raw)
    }

    public static func analysisPackageFromRawReply(
        raw: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        fallbackTitle: String
    ) -> DocumentAnalysisPackage {
        DocumentNamingReplyParser.analysisPackageFromRawReply(
            raw: raw,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            fallbackTitle: fallbackTitle
        )
    }

    public static func packageFailure(
        raw: String,
        fileModificationDate: Date,
        error: String,
        fallbackTitle: String
    ) -> DocumentAnalysisPackage {
        DocumentNamingReplyParser.packageFailure(
            raw: raw,
            fileModificationDate: fileModificationDate,
            error: error,
            fallbackTitle: fallbackTitle
        )
    }

    public static func validatedDocumentDate(iso: String?, fileModificationDate: Date) -> (Date, Bool) {
        DocumentNamingDateValidation.validatedDocumentDate(iso: iso, fileModificationDate: fileModificationDate)
    }

    public static func isWeakGenericTitle(_ slug: String) -> Bool {
        DocumentNamingReplyParser.isWeakGenericTitle(slug)
    }

    public static func repairInvalidJSONStringEscapes(_ s: String) -> String {
        DocumentNamingReplyParser.repairInvalidJSONStringEscapes(s)
    }

    public static func extractJSONObject(from raw: String) -> String {
        DocumentNamingReplyParser.extractJSONObject(from: raw)
    }
}
