import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }
}

struct L10n {
    var lang: AppLanguage

    init(_ lang: AppLanguage) {
        self.lang = lang
    }

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

    // MARK: - Onboarding

    var onboardingWelcomeTitle: String {
        s(en: "Welcome to Nomen", de: "Willkommen bei Nomen")
    }

    var onboardingWelcomeSubtitle: String {
        s(
            en: "Rename documents locally with on-device AI — private, no cloud for naming.",
            de: "Benenne Dokumente lokal mit On-Device-KI — privat, ohne Cloud für die Benennung."
        )
    }

    var onboardingStartNow: String {
        s(en: "Start now", de: "Direkt starten")
    }

    var onboardingStartNowHint: String {
        s(
            en: "Keeps recommended defaults. You can change everything later in Settings.",
            de: "Behält sinnvolle Standardwerte. Alles ist später in den Einstellungen änderbar."
        )
    }

    var onboardingConfigure: String {
        s(en: "Set up step by step", de: "Schritt für Schritt einrichten")
    }

    var onboardingConfigureHint: String {
        s(
            en: "Language, naming model, and a few workflow options.",
            de: "Sprache, Benennungs-Modell und ein paar Workflow-Optionen."
        )
    }

    var onboardingStepLanguageTitle: String {
        s(en: "Language", de: "Sprache")
    }

    var onboardingStepLanguageSubtitle: String {
        s(
            en: "How the app speaks to you and how archive titles are written.",
            de: "Wie die App dir angezeigt wird und wie Archivtitel formuliert werden."
        )
    }

    var onboardingStepNamingTitle: String {
        s(en: "Naming model", de: "Benennungs-Modell")
    }

    var onboardingStepNamingSubtitle: String {
        s(
            en: "Apple’s model is ready to use but slower and less exact; Qwen is faster and sharper after a download.",
            de: "Apples Modell ist sofort nutzbar, aber langsamer und weniger exakt; Qwen ist nach dem Download schneller und in der Regel treffsicherer."
        )
    }

    var onboardingStepMoreTitle: String {
        s(en: "Workflow & developer", de: "Workflow & Entwickler")
    }

    var onboardingStepMoreSubtitle: String {
        s(
            en: "Optional: clear the list after rename and pipeline debug for troubleshooting.",
            de: "Optional: Liste nach Umbenennen leeren und Pipeline-Debug zur Fehlersuche."
        )
    }

    var onboardingBack: String { s(en: "Back", de: "Zurück") }

    var onboardingNext: String { s(en: "Continue", de: "Weiter") }

    var onboardingFinish: String { s(en: "Done", de: "Fertig") }

    func onboardingProgress(current: Int, total: Int) -> String {
        s(en: "Step \(current) of \(total)", de: "Schritt \(current) von \(total)")
    }

    // MARK: - Settings

    var settingsTitle: String { s(en: "Settings", de: "Einstellungen") }

    var settingsSectionAppLanguage: String { s(en: "App language", de: "App-Sprache") }

    var settingsSectionTitleLanguage: String { s(en: "Title language", de: "Titelsprache") }

    var settingsSectionDeveloper: String { s(en: "Developer", de: "Entwickler") }

    var settingsSectionNamingModel: String { s(en: "Naming model", de: "Benennungs-Modell") }

    func namingInferenceLabel(_ backend: NamingInferenceBackend) -> String {
        switch backend {
        case .appleFoundation:
            return s(en: "Apple Intelligence (Foundation Model)", de: "Apple Intelligence (Foundation Model)")
        case .llamaQwenGGUF:
            return s(en: "Qwen2.5-7B-Instruct Q4_K_M (GGUF, local)", de: "Qwen2.5-7B-Instruct Q4_K_M (GGUF, lokal)")
        }
    }

    func namingInferenceHint(_ backend: NamingInferenceBackend) -> String {
        switch backend {
        case .appleFoundation:
            return s(
                en: """
                Names are often a bit less precise and each rename can take longer than with the local Qwen option. \
                Everything stays on-device: Apple’s Foundation Model needs no extra download when Apple Intelligence is available (macOS 26+).
                """,
                de: """
                Die Vorschläge sind oft etwas weniger präzise, und eine Benennung dauert in der Regel länger als mit dem lokalen Qwen-Modell. \
                Dafür läuft alles On-Device: Apples Foundation Model erfordert keinen separaten Download, sofern Apple Intelligence unter macOS 26+ verfügbar ist.
                """
            )
        case .llamaQwenGGUF:
            return s(
                en: """
                Typically more accurate titles and much faster naming. Llama.cpp runs fully on your Mac. \
                You need a one-time download of the GGUF shards (~\(QwenGGUFModelSupport.approximateDownloadMegabytes) MB total).
                """,
                de: """
                In der Regel treffendere Titel und deutlich schnellere Benennung. Llama.cpp läuft vollständig auf deinem Mac. \
                Es ist ein einmaliger Download der GGUF-Teile nötig (insgesamt ~\(QwenGGUFModelSupport.approximateDownloadMegabytes) MB).
                """
            )
        }
    }

    var ggufDownloadButton: String { s(en: "Download model…", de: "Modell laden …") }

    var ggufDownloadedLabel: String { s(en: "Model file is present.", de: "Modell-Datei ist vorhanden.") }

    var ggufRevealInFinder: String { s(en: "Reveal in Finder", de: "Im Finder zeigen") }

    var ggufDownloadConfirmTitle: String {
        s(en: "Download model file?", de: "Modell-Datei laden?")
    }

    var ggufDownloadConfirmMessage: String {
        s(
            en: "The app will download about \(QwenGGUFModelSupport.approximateDownloadMegabytes) MB from Hugging Face (Qwen2.5-7B-Instruct-GGUF, Q4_K_M, two parts). Wi‑Fi recommended.",
            de: "Die App lädt etwa \(QwenGGUFModelSupport.approximateDownloadMegabytes) MB von Hugging Face (Qwen2.5-7B-Instruct-GGUF, Q4_K_M, zwei Teile). WLAN empfohlen."
        )
    }

    var ggufDownloading: String { s(en: "Downloading…", de: "Lade herunter …") }

    func ggufDownloadProgressPercent(_ percent: Int) -> String {
        let p = min(100, max(0, percent))
        return s(en: "\(p) % complete", de: "\(p) % fertig")
    }

    func ggufDownloadFailed(_ detail: String) -> String {
        s(en: "Download failed: \(detail)", de: "Download fehlgeschlagen: \(detail)")
    }

    var languageLabel: String { s(en: "Language", de: "Sprache") }

    var outputLanguageLabel: String { s(en: "Archive title language", de: "Sprache der Archivtitel") }

    func outputLanguageModeLabel(_ mode: OutputLanguageMode) -> String {
        switch mode {
        case .followDocument:
            return s(en: "Follow document language", de: "Sprache des Dokuments")
        case .appLanguage:
            return s(en: "Always use app language", de: "Immer App-Sprache verwenden")
        }
    }

    func outputLanguageHint(_ mode: OutputLanguageMode) -> String {
        switch mode {
        case .followDocument:
            return s(
                en: "German doc → German title, French doc → French title, etc.",
                de: "Deutsches Dokument → deutscher Titel, französisches → französischer Titel usw."
            )
        case .appLanguage:
            return s(
                en: "All titles are written in the app language set above.",
                de: "Alle Titel werden in der oben gewählten App-Sprache ausgegeben."
            )
        }
    }

    var debugPipelineToggle: String {
        s(en: "Show pipeline debug", de: "Pipeline-Debug anzeigen")
    }

    var debugPipelineHint: String {
        s(en: "Shows text extraction and raw model output below the file list.",
          de: "Zeigt Textextraktion und Modell-Rohantwort unterhalb der Dateiliste.")
    }

    var debugInspectorHint: String {
        s(en: "Select one row to see extraction and model steps.", de: "Eine Zeile wählen, um Extraktion und Modell-Schritte zu sehen.")
    }

    var debugInspectorTitle: String {
        s(en: "Pipeline debug", de: "Pipeline-Debug")
    }

    var debugInspectorNoData: String {
        s(
            en: "No snapshot for this row. Turn on pipeline debug in Settings, then add the files again.",
            de: "Keine Aufzeichnung für diese Zeile. Pipeline-Debug in den Einstellungen aktivieren und Dateien erneut hinzufügen."
        )
    }

    var pipelineDebugHeaders: PipelineDebugL10n {
        PipelineDebugL10n(
            step1: s(en: "1 · Text extraction", de: "1 · Text extrahieren"),
            step2: s(en: "2 · Text sent to model (sample)", de: "2 · Text ans Modell (Ausschnitt)"),
            step3: s(en: "3 · Raw model reply", de: "3 · Rohe Modell-Antwort"),
            step4: s(en: "4 · Parsed JSON fields", de: "4 · Gelesene JSON-Felder"),
            step5: s(en: "5 · Final values used", de: "5 · Finale verwendete Werte"),
            embeddedChars: s(en: "Embedded PDF characters", de: "Eingebetteter PDF-Text (Zeichen)"),
            ocrChars: s(en: "OCR characters", de: "OCR-Zeichen"),
            chosen: s(en: "Chosen for model", de: "Fürs Modell verwendet"),
            totalChars: s(en: "Total characters in excerpt", de: "Zeichen im Ausschnitt"),
            error: s(en: "Error", de: "Fehler"),
            titleUsed: s(en: "Title after sanitize", de: "Titel nach Bereinigung"),
            dateFromDoc: s(en: "Date from document", de: "Datum aus Dokument"),
            fallbackStem: s(en: "Used filename stem fallback", de: "Fallback auf Dateinamen-Stamm"),
            yes: s(en: "yes", de: "ja"),
            no: s(en: "no", de: "nein")
        )
    }

    // MARK: - About / App menu

    var aboutMenu: String { s(en: "About Nomen…", de: "Über Nomen…") }

    var aboutCopyright: String {
        "© 2026 Dr. med. Ansgar Scheffold"
    }

    var aboutCredits: String {
        s(
            en: """
            PDFs with embedded text (digital invoices etc.) are read directly via PDFKit (up to 40 pages). \
            Scanned PDFs fall back to Vision OCR on the first page. Other file types: PDFKit or plain text. \
            Naming uses either Apple’s on-device Foundation Models (Apple Intelligence, macOS 26+) or an optional local GGUF model (Qwen2.5-7B via llama.cpp), chosen in Settings.

            Everything runs locally — no cloud API calls for naming; the GGUF is downloaded once if you enable it. \
            .docx is read locally via ZIP/XML extraction. Legacy .doc is not supported.
            """,
            de: """
            PDFs mit eingebettetem Text (digitale Rechnungen usw.) werden direkt via PDFKit gelesen (bis zu 40 Seiten). \
            Gescannte PDFs nutzen Vision-OCR auf der ersten Seite als Fallback. Andere Dateitypen: PDFKit oder Klartext. \
            Benennung entweder mit Apples On-Device Foundation Models (Apple Intelligence, macOS 26+) oder optional mit einem lokalen GGUF-Modell (Qwen2.5-7B via llama.cpp), wählbar in den Einstellungen.

            Alles läuft lokal — keine Cloud-APIs für die Benennung; das GGUF wird bei Bedarf einmal heruntergeladen. \
            .docx wird lokal via ZIP/XML-Extraktion gelesen. Klassisches .doc wird nicht unterstützt.
            """
        )
    }

    // MARK: - Schema

    func schemaMenuLabel(_ schema: DateNameSchema) -> String {
        switch schema {
        case .yearMonthTitle:
            return s(en: "YYYY MM + title", de: "YYYY MM + Titel")
        case .compactDateTitle:
            return s(en: "YYMMDD + title", de: "YYMMDD + Titel")
        case .titleOnly:
            return s(en: "Title only", de: "Nur Titel")
        }
    }

    func schemaDetailHint(_ schema: DateNameSchema) -> String {
        switch schema {
        case .yearMonthTitle:
            return s(en: "e.g. “2026 04 Invoice iPhone”", de: "z. B. „2026 04 Rechnung iPhone“")
        case .compactDateTitle:
            return s(en: "e.g. “260410 Invoice iPhone”", de: "z. B. „260410 Rechnung iPhone“")
        case .titleOnly:
            return s(en: "e.g. “Invoice iPhone”", de: "z. B. „Rechnung iPhone“")
        }
    }

    private func s(en: String, de: String) -> String {
        switch lang {
        case .english: return en
        case .german: return de
        }
    }
}
