import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Wie im Apple Code-Along (Kap. 6): Modell früh laden, erste Anfrage wirkt schneller.
@available(macOS 26.0, *)
@MainActor
enum FoundationModelPrewarm {
    private static var didRun = false

    static func prewarmOnceIfAvailable() {
        guard !didRun else { return }
        didRun = true

        guard case .available = SystemLanguageModel.default.availability else { return }

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: "Assistant for local document tasks."
        )
        session.prewarm()
    }
}
#endif
