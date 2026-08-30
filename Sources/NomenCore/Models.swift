import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case german = "de"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }
}

public enum OutputLanguageMode: String, CaseIterable, Identifiable, Sendable {
    case followDocument = "followDocument"
    case appLanguage = "appLanguage"

    public var id: String { rawValue }
}

/// Quelle für die Archiv-Titel-Extraktion (Apple Intelligence vs. lokales GGUF).
public enum NamingInferenceBackend: String, CaseIterable, Identifiable, Sendable {
    case appleFoundation = "appleFoundation"
    case llamaQwenGGUF = "llamaQwenGGUF"

    public var id: String { rawValue }

    /// Früherer `@AppStorage`-Wert (H2O Danube); auf Qwen migrieren.
    public static let legacyLlamaDanubeRawValue = "llamaDanubeGGUF"

    /// Normalisiert gespeicherte Backend-Rohwerte nach App-Updates.
    public static func normalizedInferenceStorageRawValue(_ stored: String) -> String {
        if stored == legacyLlamaDanubeRawValue { return llamaQwenGGUF.rawValue }
        return stored
    }
}

public enum DateNameSchema: String, CaseIterable, Identifiable {
    case yearMonthTitle = "yyyyMM_title"
    case compactDateTitle = "yyMMdd_title"
    case titleOnly = "title_only"

    public var id: String { rawValue }
}

/// Result of on-device model analysis (or minimal fallback when the model is unavailable).
public struct DocumentUnderstandingResult: Sendable, Hashable {
    public let title: String
    public let documentDate: Date?
    public let usedContentDate: Bool

    public init(title: String, documentDate: Date?, usedContentDate: Bool) {
        self.title = title
        self.documentDate = documentDate
        self.usedContentDate = usedContentDate
    }

    public static func filenameFallback(
        fallbackFilenameStem: String,
        fileModificationDate: Date
    ) -> DocumentUnderstandingResult {
        DocumentUnderstandingResult(
            title: FilenameSanitizer.archiveFallbackTitle(fromFilenameStem: fallbackFilenameStem),
            documentDate: fileModificationDate,
            usedContentDate: false
        )
    }
}

public struct RenamePreviewRow: Identifiable, Hashable {
    public let id: UUID
    public var sourceURL: URL
    /// Dateiname vor der letzten Umbenennung in dieser Sitzung; nach erfolgreichem Rename wird er dem neuen Namen angeglichen, wenn die Liste stehen bleibt.
    public var originalName: String
    public var proposedName: String
    public var statusMessage: String?
    public var usedFallbackDate: Bool
    /// Cached understanding so changing naming pattern does not re-scan files.
    public var namingBasis: DocumentUnderstandingResult?
    /// Filled when pipeline debug is enabled in Settings.
    public var pipelineDebug: PipelineDebugSnapshot?
    /// Zeile wartet noch auf OCR/KI — für Live-Liste und Abbruch-Logik.
    public var isAnalysisPlaceholder: Bool = false

    public var proposedURL: URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(proposedName)
    }

    public init(
        id: UUID,
        sourceURL: URL,
        originalName: String,
        proposedName: String,
        statusMessage: String?,
        usedFallbackDate: Bool,
        namingBasis: DocumentUnderstandingResult?,
        pipelineDebug: PipelineDebugSnapshot?,
        isAnalysisPlaceholder: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.originalName = originalName
        self.proposedName = proposedName
        self.statusMessage = statusMessage
        self.usedFallbackDate = usedFallbackDate
        self.namingBasis = namingBasis
        self.pipelineDebug = pipelineDebug
        self.isAnalysisPlaceholder = isAnalysisPlaceholder
    }
}

public enum RenameAnalysisPhase: String {
    case idle
    case extracting
    case ocr
    case understanding
    case ready
}

/// Kurzes UI-Feedback beim Umbenennen (Toolbar, Tabelle bleibt sichtbar).
public enum RenameFeedbackPhase: Equatable {
    case idle
    case working(done: Int, total: Int)
    case outcome(kind: RenameOutcomeKind, renamedCount: Int, renamedEntireList: Bool)
}

public enum RenameOutcomeKind: Equatable {
    /// Alle geplanten Umbenennungen ohne Fehler durchgelaufen.
    case success
    case partialFailure
    case allFailed
}

/// Antwort-Struktur für die Umbenennung (Apple Foundation Models und GGUF).
/// **Single source of truth:** Nur `archiveTitle` (plus `date`).
public struct RenameResult: Sendable {
    public let date: String?
    /// Der komplette, menschlich formulierte Archiv-Titel (ohne Datum). Wird nur an `FilenameSanitizer.slugTitle` übergeben.
    public let archiveTitle: String?

    /// Roh-Titel für Debug/Pipeline (nach Whitespace-Trim).
    public var generatedTitle: String {
        archiveTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public init(date: String?, archiveTitle: String?) {
        self.date = date
        self.archiveTitle = archiveTitle
    }
}
