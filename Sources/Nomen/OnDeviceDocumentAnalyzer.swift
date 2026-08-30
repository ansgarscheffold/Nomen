import Foundation
import NomenCore
import os.log

enum DocumentNamingBackendFactory {
    static func make(for backend: NamingInferenceBackend) -> any DocumentNamingBackend {
        switch backend {
        case .llamaQwenGGUF:
            return LlamaQwenNamingBackend()
        case .appleFoundation:
            return AppleFoundationNamingBackend()
        }
    }
}

struct LlamaQwenNamingBackend: DocumentNamingBackend {
    func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode
    ) async -> DocumentAnalysisPackage {
        await DocumentLlamaNaming.analyzePackage(
            sampleText: sampleText,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            localeIdentifier: localeIdentifier,
            outputLanguageMode: outputLanguageMode
        )
    }
}

struct AppleFoundationNamingBackend: DocumentNamingBackend {
    func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode
    ) async -> DocumentAnalysisPackage {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
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
}

enum OnDeviceDocumentAnalyzer {
    private static let log = Logger(subsystem: NomenLog.subsystem, category: "analysis")

    static func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode,
        inferenceBackend: NamingInferenceBackend
    ) async -> DocumentAnalysisPackage {
        log.debug("analyzePackage (\(inferenceBackend.rawValue, privacy: .public)) excerpt length=\(sampleText.count, privacy: .public)")
        let backend = DocumentNamingBackendFactory.make(for: inferenceBackend)
        return await backend.analyzePackage(
            sampleText: sampleText,
            fileModificationDate: fileModificationDate,
            fallbackFilenameStem: fallbackFilenameStem,
            localeIdentifier: localeIdentifier,
            outputLanguageMode: outputLanguageMode
        )
    }

    static func fallbackWithoutModel(
        fallbackFilenameStem: String,
        fileModificationDate: Date
    ) -> DocumentUnderstandingResult {
        DocumentUnderstandingResult.filenameFallback(
            fallbackFilenameStem: fallbackFilenameStem,
            fileModificationDate: fileModificationDate
        )
    }
}
