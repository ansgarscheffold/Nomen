import Foundation
import NomenCore

extension L10n {
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

}
