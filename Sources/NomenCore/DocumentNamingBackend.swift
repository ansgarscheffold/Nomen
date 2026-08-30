import Foundation

/// Gemeinsame Inferenz-Schnittstelle für Apple Foundation Models und lokales GGUF.
public protocol DocumentNamingBackend: Sendable {
    func analyzePackage(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        localeIdentifier: String,
        outputLanguageMode: OutputLanguageMode
    ) async -> DocumentAnalysisPackage
}
