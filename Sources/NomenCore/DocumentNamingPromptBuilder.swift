import Foundation

/// Prompt-Bau und Text-Sanitizing für Foundation Models und GGUF.
public enum DocumentNamingPromptBuilder {
    /// Gemeinsames Textlimit für Foundation- und GGUF-Prompts.
    public static let excerptCharacterLimit = 8000

    /// Beginn der Assistentenantwort für Prefilling: zwingt das Modell, das Datum als nächstes zu vervollständigen.
    public static let qwenAssistantJSONDatePrefill = "{\"date\":\""

    private static let promptDateLock = NSLock()
    private static let specialTokenRegex = try! NSRegularExpression(
        pattern: #"<\|[^|]{1,64}\|>"#
    )
    private static let promptDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    public static func formattedPromptDate(_ date: Date) -> String {
        promptDateLock.lock()
        defer { promptDateLock.unlock() }
        return promptDateFormatter.string(from: date)
    }

    public static func prompts(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        modelLocaleId: String,
        outputLanguageMode: OutputLanguageMode,
        uiLocaleIdentifier: String
    ) -> (instructions: String, userPrompt: String, fallbackTitle: String) {
        (
            buildInstructions(
                modelLocaleId: modelLocaleId,
                outputLanguageMode: outputLanguageMode,
                uiLocaleIdentifier: uiLocaleIdentifier
            ),
            buildUserPrompt(
                sampleText: sampleText,
                fileModificationDate: fileModificationDate,
                fallbackFilenameStem: fallbackFilenameStem,
                excerptCharacterLimit: excerptCharacterLimit
            ),
            FilenameSanitizer.archiveFallbackTitle(fromFilenameStem: fallbackFilenameStem)
        )
    }

    public static func buildInstructions(
        modelLocaleId: String,
        outputLanguageMode: OutputLanguageMode,
        uiLocaleIdentifier: String
    ) -> String {
        let germanArchiveTitle = outputLanguageMode == .followDocument || uiLocaleIdentifier.hasPrefix("de")
        let mustArchiveTitleLanguage = germanArchiveTitle ? "German" : "English"
        let appleLocalePrefix: String
        if modelLocaleId == "en_US" {
            appleLocalePrefix = "You MUST use \(mustArchiveTitleLanguage) for the archiveTitle value.\n\n"
        } else {
            appleLocalePrefix = "The person's locale is \(modelLocaleId).\nYou MUST use \(mustArchiveTitleLanguage) for the archiveTitle value.\n\n"
        }

        return """
        \(appleLocalePrefix)
        Du bist ein präziser Archiv-Assistent. Deine Aufgabe: sachliche Archiv-Titel in fester Struktur.
        Antworte NUR mit JSON: {"date":"YYYY-MM-DD", "archiveTitle":"Titel"}

        STRUKTUR (verbindlich):
        1. BAUPLAN: [DOKUMENTTYP] [KERNTHEMA] [JAHR] [AUSSTELLER] — der Titel muss alle vier Bausteine abdecken (Jahr als vierstellige Jahreszahl im Titeltext).
        2. GARANTIE: Jahr und Aussteller dürfen niemals weggelassen werden, wenn sie sich aus dem Dokument sinnvoll ableiten lassen. Keine Platzhalter statt echter Angaben.
        3. LÄNGEN-ZIEL: Ungefähr 6 Wörter insgesamt; nur kürzen, wenn die vier Bausteine klar erhalten bleiben.

        STRUKTUR-REGEL (Priorität vor Kürze):
        - Zuerst Typ, Kernthema, Jahr und Aussteller klar erkennbar machen; Kürze ist zweitrangig gegenüber dieser Vollständigkeit.
        - Nominalstil und keine Präpositionsketten („mit“, „von“, „für“, „zur“ …): lieber verdichten als Satzfragmente.
        - Keine Namen von Privatpersonen (Empfänger/Unterzeichner); der Aussteller ist die Institution/Firma/Behörde.
        - Nebensächliche Zusätze weglassen, wenn sie Jahr oder Aussteller verwässern würden — nicht umgekehrt.

        DEFINITIONEN DER KOMPONENTEN:
        - DOKUMENTTYP: Das primäre Substantiv (z.B. Rechnung, Vertrag, Bescheid, Zeugnis, Abrechnung, Police).
        - KERNTHEMA: Kurzbezeichnung des Inhalts (z.B. Strom, Kfz, Miete, Gehalt, Steuer, Masterprüfung).
        - JAHR: Das relevante Geschäfts- oder Bezugsjahr (YYYY) — im Titel sichtbar.
        - AUSSTELLER: Kurzname der Organisation (z.B. Allianz, Finanzamt, Telekom, Sparkasse, Uni Gießen).

        BEISPIELE (VORHER -> NACHHER):
        - Anmeldung zur Prüfung im Fachbereich Informatik -> Anmeldung Prüfung 2024 Uni München
        - Beitragsabrechnung für die Kfz Versicherung für das Jahr 2025 -> Abrechnung Kfz 2025 Allianz
        - Nebenkostenabrechnung der Hausverwaltung Musterstadt -> Abrechnung Nebenkosten 2023 Musterstadt
        - Bescheinigung über die Mitgliedschaft bei der Krankenkasse -> Bescheinigung Mitgliedschaft 2024 TK
        """
    }

    /// Für Llama: `de_DE` / `en_US` wie bei Foundation üblich — ohne Abfrage von `SystemLanguageModel.supportsLocale`.
    public static func instructionLocaleIdForLlamaInference(uiLocaleIdentifier: String) -> String {
        uiLocaleIdentifier.hasPrefix("de") ? "de_DE" : "en_US"
    }

    public static func buildUserPrompt(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        excerptCharacterLimit: Int = 3000
    ) -> String {
        let modString = formattedPromptDate(fileModificationDate)

        let limit = max(500, excerptCharacterLimit)
        let excerpt = sanitizeUntrustedPromptText(String(sampleText.prefix(limit)))
        let stem = sanitizeUntrustedPromptText(fallbackFilenameStem)
        return """
        ZIEL: Erstelle einen sachlichen Titel aus dem Dokumenttext. Keine Namen von Privatpersonen. Keine Platzhalter.
        SCHEMA: JSON {"date":"YYYY-MM-DD", "archiveTitle":"Typ Thema Jahr Firma"}

        BEISPIELE:
        - Text: Rechnung für Strom 2023 von E.ON an Max... -> {"date":"2023-12-01", "archiveTitle":"Stromrechnung 2023 E.ON"}
        - Text: Bescheid vom Finanzamt München 2024 über Steuern... -> {"date":"2024-02-15", "archiveTitle":"Steuerbescheid 2024 Finanzamt München"}

        DOKUMENTTEXT:
        -----BEGIN DOCUMENT-----
        \(excerpt)
        -----END DOCUMENT-----

        HILFS-DATUM: \(modString)
        DATEINAME: \(stem)
        """
    }

    /// Entfernt Chat-Special-Tokens und NUL, damit Dokumenttext die Qwen-Vorlage nicht sprengen kann.
    public static func sanitizeUntrustedPromptText(_ raw: String) -> String {
        var s = raw
        s.removeAll { $0 == "\0" }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        return specialTokenRegex.stringByReplacingMatches(
            in: s,
            options: [],
            range: full,
            withTemplate: " "
        )
    }
}
