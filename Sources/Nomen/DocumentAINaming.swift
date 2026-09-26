import Foundation
import NomenCore
import os.log

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
            log.error("SystemLanguageModel unavailable: \(desc, privacy: .private)")
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
            var options = GenerationOptions()
            options.temperature = 0.0

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
            log.error("Model call failed: \(String(describing: error), privacy: .private)")
            return DocumentAnalysisPackage.titledFallback(
                title: fallbackTitle,
                fileModificationDate: fileModificationDate,
                errorStep: error.localizedDescription
            )
        }
    }
}
#endif
