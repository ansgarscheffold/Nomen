import Foundation
import os.log
import NomenCore

/// On-Device-Benennung mit lokalem GGUF (Qwen2.5-7B-Instruct) über llama.cpp — gleiche Prompts wie Foundation + JSON-Prefill.
enum DocumentLlamaNaming {
    private static let log = Logger(subsystem: NomenLog.subsystem, category: "DocumentLlamaNaming")

    static func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode
    ) async -> DocumentAnalysisPackage {
        guard QwenGGUFModelSupport.isDownloaded else {
            return DocumentAnalysisPackage.filenameFallback(
                fallbackFilenameStem: fallbackFilenameStem,
                fileModificationDate: fileModificationDate,
                errorStep: String(describing: DocumentAnalysisError.ggufModelFileMissing)
            )
        }

        let modelLocaleId = DocumentNamingPipeline.instructionLocaleIdForLlamaInference(
            uiLocaleIdentifier: localeIdentifier
        )
        let (instructions, userPrompt, fallbackTitle) = DocumentNamingPipeline.prompts(
            sampleText: sampleText,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            modelLocaleId: modelLocaleId,
            outputLanguageMode: outputLanguageMode,
            uiLocaleIdentifier: localeIdentifier
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
            return DocumentAnalysisPackage.titledFallback(
                title: fallbackTitle,
                fileModificationDate: fileModificationDate,
                errorStep: error.localizedDescription
            )
        }
    }
}
