import Foundation
import os.log

/// On-Device-Benennung mit lokalem GGUF (Qwen2.5-7B-Instruct) über llama.cpp — gleiche Prompts wie Foundation + JSON-Prefill.
enum DocumentLlamaNaming {
    private static let log = Logger(subsystem: "nomen", category: "DocumentLlamaNaming")

    static func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode
    ) async -> DocumentAnalysisPackage {
        let fallbackTitleStem = FilenameSanitizer.cleanStemForTitle(fallbackFilenameStem)
        let fallbackTitle = fallbackTitleStem.isEmpty ? "Document" : fallbackTitleStem

        guard QwenGGUFModelSupport.isDownloaded else {
            let fb = OnDeviceDocumentAnalyzer.fallbackWithoutModel(
                fallbackFilenameStem: fallbackFilenameStem,
                fileModificationDate: fileModificationDate
            )
            return DocumentAnalysisPackage(
                result: fb,
                modelRawReply: nil,
                jsonSuggestedTitle: nil,
                jsonDocumentDateISO: nil,
                jsonDateFromDocument: nil,
                errorStep: String(describing: DocumentAnalysisError.ggufModelFileMissing),
                usedFilenameFallbackForTitle: true
            )
        }

        let modelLocaleId = DocumentNamingPipeline.instructionLocaleIdForLlamaInference(
            uiLocaleIdentifier: localeIdentifier
        )
        let instructions = DocumentNamingPipeline.buildInstructions(
            modelLocaleId: modelLocaleId,
            outputLanguageMode: outputLanguageMode,
            uiLocaleIdentifier: localeIdentifier
        )
        let userPrompt = DocumentNamingPipeline.buildUserPrompt(
            sampleText: sampleText,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            excerptCharacterLimit: 8000
        )
        let datePrefill = DocumentNamingPipeline.qwenAssistantJSONDatePrefill
        let fullPrompt = Qwen25InstructChatTemplate.buildPrompt(
            systemInstructions: instructions,
            userContent: userPrompt,
            assistantPrefill: datePrefill
        )

        let path = QwenGGUFModelSupport.localFileURL.path

        do {
            try await LlamaCppRunner.shared.ensureLoaded(modelPath: path)
            let generated = try await LlamaCppRunner.shared.generateContinuation(
                afterFullPrompt: fullPrompt,
                jsonLeadIn: datePrefill
            )
            let combined = datePrefill + generated.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = DocumentNamingPipeline.truncateToFirstBalancedJSONObject(combined)
            log.debug("GGUF raw reply length=\(raw.count, privacy: .public)")
            return DocumentNamingPipeline.analysisPackageFromRawReply(
                raw: raw,
                fileModificationDate: fileModificationDate,
                fallbackFilenameStem: fallbackFilenameStem,
                fallbackTitle: fallbackTitle
            )
        } catch {
            log.error("Llama inference failed: \(String(describing: error), privacy: .public)")
            let fb = DocumentUnderstandingResult(
                title: fallbackTitle,
                documentDate: fileModificationDate,
                usedContentDate: false
            )
            return DocumentAnalysisPackage(
                result: fb,
                modelRawReply: nil,
                jsonSuggestedTitle: nil,
                jsonDocumentDateISO: nil,
                jsonDateFromDocument: nil,
                errorStep: error.localizedDescription,
                usedFilenameFallbackForTitle: true
            )
        }
    }
}
