import Foundation
import NomenCore

extension L10n {
    // MARK: - Main

    var windowTitleDocuments: String { s(en: "Documents", de: "Dokumente") }

    var localOnlyBadge: String { s(en: "Local only", de: "Nur lokal") }

    var clear: String { s(en: "Clear", de: "Leeren") }

    var dialogCancel: String { s(en: "Cancel", de: "Abbrechen") }

    var alertErrorTitle: String { s(en: "Error", de: "Fehler") }

    var dialogOK: String { s(en: "OK", de: "OK") }

    var stop: String { s(en: "Stop", de: "Stopp") }

    var analysisStopped: String {
        s(en: "Analysis stopped — partial results kept.", de: "Analyse abgebrochen — Teilergebnisse bleiben.")
    }

    var rowPendingAnalysis: String {
        s(en: "Analyzing…", de: "Analyse läuft…")
    }

    var rename: String { s(en: "Rename", de: "Umbenennen") }

    var renameAll: String { s(en: "Rename all", de: "Alle umbenennen") }

    var openPanelPrompt: String { s(en: "Open", de: "Öffnen") }

    var dropHeadline: String { s(en: "Drop PDFs and documents here", de: "PDFs und Dokumente hierher ziehen") }

    var dropSubline: String { s(en: "Or click to choose files · pdf, txt, md, rtf, docx", de: "Oder klicken zum Auswählen · pdf, txt, md, rtf, docx") }

    var namingPattern: String { s(en: "Naming pattern", de: "Namensmuster") }

    var columnOldName: String { s(en: "Current name", de: "Alter Name") }

    var columnNewName: String { s(en: "New name (preview)", de: "Neuer Name (Vorschau)") }

    var columnHint: String { s(en: "Note", de: "Hinweis") }

    // MARK: - Context menu

    var contextRenameSelected: String { s(en: "Rename", de: "Umbenennen") }
    var contextRemoveFromList: String { s(en: "Remove from List", de: "Aus Liste entfernen") }
    var contextShowInFinder: String { s(en: "Show in Finder", de: "Im Finder anzeigen") }

    var emptyNoFilesTitle: String { s(en: "No files yet", de: "Noch keine Dateien") }

    var emptyNoFilesDescription: String {
        s(en: "Drop files in the area above or click to browse. The preview appears here.",
          de: "Ziehe Dateien in den Bereich oben oder klicke zum Durchsuchen. Die Vorschau erscheint hier.")
    }

    var emptyErrorTitle: String { s(en: "Could not analyze", de: "Keine Analyse möglich") }

    var progressNeural: String {
        s(en: "Analyzing on-device (Neural Engine)…", de: "Analysiere lokal auf deiner Neural Engine…")
    }

    var progressExtract: String { s(en: "Extracting text (PDFKit)…", de: "Text extrahieren (PDFKit)…") }

    var progressOCR: String { s(en: "OCR with Vision (on-device)…", de: "OCR mit Vision (lokal)…") }

    /// Mehrere **Dateien** in einem Durchlauf (nicht PDF-Seiten).
    func progressDocumentsBatch(current: Int, total: Int) -> String {
        s(en: "File \(current) of \(total)", de: "Datei \(current) von \(total)")
    }

    func progressNL(inferenceBackend: NamingInferenceBackend) -> String {
        switch inferenceBackend {
        case .appleFoundation:
            return s(
                en: "Naming with on-device language model (Apple Intelligence)…",
                de: "Benennung mit On-Device-Sprachmodell (Apple Intelligence)…"
            )
        case .llamaQwenGGUF:
            return s(
                en: "Naming with on-device Qwen2.5-7B (GGUF via llama.cpp)…",
                de: "Benennung mit lokalem Qwen2.5-7B (GGUF via llama.cpp)…"
            )
        }
    }

    var modelFallbackHint: String {
        s(
            en: "Model unavailable — using file name and file date only.",
            de: "Modell nicht verfügbar — nur Dateiname und Dateidatum."
        )
    }

    /// Shown when `SystemLanguageModel` ran but the reply was not usable JSON.
    var modelJSONParseFallbackHint: String {
        s(
            en: "On-device model replied, but the answer was not usable JSON — using file name and file date.",
            de: "Das On-Device-Modell hat geantwortet, aber die Antwort war kein verwertbares JSON — Dateiname und Dateidatum."
        )
    }

    /// Other generation / encoding errors while calling the model.
    var modelCallFallbackHint: String {
        s(
            en: "On-device naming failed — using file name and file date.",
            de: "On-Device-Benennung fehlgeschlagen — Dateiname und Dateidatum."
        )
    }

    func modelFallbackUserMessage(detail: String) -> String {
        let d = detail.lowercased()
        if d.contains("json decode") || d.contains("could not encode") || d.contains("not usable json") {
            return "\(modelJSONParseFallbackHint) (\(detail))"
        }
        if d.contains("unavailable") {
            return "\(modelFallbackHint) (\(detail))"
        }
        return "\(modelCallFallbackHint) (\(detail))"
    }

    var progressDone: String {
        s(en: "Done — review the preview below.", de: "Fertig – Vorschau unten prüfen.")
    }

    var dateFromContent: String { s(en: "Date from content", de: "Datum aus Inhalt") }

    var dateFromFile: String { s(en: "Date from file", de: "Datum aus Datei") }

    var dateMetaCaption: String { s(en: "Date: file metadata", de: "Datum: Datei-Metadaten") }

    var renamed: String { s(en: "Renamed", de: "Umbenannt") }

    func renameError(_ message: String) -> String {
        s(en: "Error: \(message)", de: "Fehler: \(message)")
    }

    var renameWorkingPreparing: String {
        s(en: "Renaming…", de: "Umbenennen …")
    }

    func renameWorkingProgress(done: Int, total: Int) -> String {
        s(en: "\(done) of \(total) files done", de: "\(done) von \(total) Dateien erledigt")
    }

    var renameSuccessTitle: String {
        s(en: "All files renamed", de: "Alle Dateien umbenannt")
    }

    var renameSuccessSingle: String {
        s(en: "1 file renamed", de: "1 Datei umbenannt")
    }

    func renameSuccessSubset(count: Int) -> String {
        s(en: "\(count) files renamed", de: "\(count) Dateien umbenannt")
    }

    func renameSuccessSummary(count: Int, entireList: Bool) -> String {
        if entireList { return renameSuccessTitle }
        if count == 1 { return renameSuccessSingle }
        return renameSuccessSubset(count: count)
    }

    var renamePartialTitle: String {
        s(en: "Some files could not be renamed", de: "Einige Dateien konnten nicht umbenannt werden")
    }

    var renameAllFailedTitle: String {
        s(en: "Renaming failed", de: "Umbenennen fehlgeschlagen")
    }

    var settingsSectionWorkflow: String { s(en: "After renaming", de: "Nach dem Umbenennen") }

    var settingsClearListAfterRename: String {
        s(en: "Clear list when all files were renamed successfully", de: "Liste leeren, wenn alle Dateien erfolgreich umbenannt wurden")
    }

    var settingsClearListAfterRenameHint: String {
        s(
            en: "When off, the table stays open so you can review names or rename again.",
            de: "Wenn aus, bleibt die Tabelle offen — zum Prüfen oder erneuten Umbenennen."
        )
    }


    var noSupportedFiles: String {
        s(en: "No supported files (pdf, txt, md, rtf, docx).", de: "Keine unterstützten Dateien (pdf, txt, md, rtf, docx).")
    }

    var dropCouldNotReadURLs: String {
        s(
            en: "Could not read the dropped items as file paths. Try “Open” in the drop area or drag from a local folder.",
            de: "Die abgelegten Elemente konnten nicht als Dateipfade gelesen werden. Versuche „Öffnen“ im Ablagefeld oder Ziehen aus einem lokalen Ordner."
        )
    }

}
