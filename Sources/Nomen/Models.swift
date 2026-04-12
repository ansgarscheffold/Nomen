import Foundation

enum OutputLanguageMode: String, CaseIterable, Identifiable {
    case followDocument = "followDocument"
    case appLanguage = "appLanguage"

    var id: String { rawValue }
}

/// Quelle für die Archiv-Titel-Extraktion (Apple Intelligence vs. lokales GGUF).
enum NamingInferenceBackend: String, CaseIterable, Identifiable {
    case appleFoundation = "appleFoundation"
    case llamaQwenGGUF = "llamaQwenGGUF"

    var id: String { rawValue }

    /// Früherer `@AppStorage`-Wert (H2O Danube); auf Qwen migrieren.
    static let legacyLlamaDanubeRawValue = "llamaDanubeGGUF"

    /// Normalisiert gespeicherte Backend-Rohwerte nach App-Updates.
    static func normalizedInferenceStorageRawValue(_ stored: String) -> String {
        if stored == legacyLlamaDanubeRawValue { return llamaQwenGGUF.rawValue }
        return stored
    }
}

enum DateNameSchema: String, CaseIterable, Identifiable {
    case yearMonthTitle = "yyyyMM_title"
    case compactDateTitle = "yyMMdd_title"
    case titleOnly = "title_only"

    var id: String { rawValue }
}

/// Result of on-device model analysis (or minimal fallback when the model is unavailable).
struct DocumentUnderstandingResult: Sendable, Hashable {
    let title: String
    let documentDate: Date?
    let usedContentDate: Bool
}

struct RenamePreviewRow: Identifiable, Hashable {
    let id: UUID
    var sourceURL: URL
    /// Dateiname vor der letzten Umbenennung in dieser Sitzung; nach erfolgreichem Rename wird er dem neuen Namen angeglichen, wenn die Liste stehen bleibt.
    var originalName: String
    var proposedName: String
    var statusMessage: String?
    var usedFallbackDate: Bool
    /// Cached understanding so changing naming pattern does not re-scan files.
    var namingBasis: DocumentUnderstandingResult?
    /// Filled when pipeline debug is enabled in Settings.
    var pipelineDebug: PipelineDebugSnapshot?
    /// Zeile wartet noch auf OCR/KI — für Live-Liste und Abbruch-Logik.
    var isAnalysisPlaceholder: Bool = false

    var proposedURL: URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(proposedName)
    }
}

enum RenameAnalysisPhase: String {
    case idle
    case extracting
    case ocr
    case understanding
    case ready
}

/// Kurzes UI-Feedback beim Umbenennen (Toolbar, Tabelle bleibt sichtbar).
enum RenameFeedbackPhase: Equatable {
    case idle
    case working(done: Int, total: Int)
    case outcome(kind: RenameOutcomeKind, renamedCount: Int, renamedEntireList: Bool)
}

enum RenameOutcomeKind: Equatable {
    /// Alle geplanten Umbenennungen ohne Fehler durchgelaufen.
    case success
    case partialFailure
    case allFailed
}
