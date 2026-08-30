import Foundation

/// Gemeinsame Prompt-Texte und JSON-Auswertung für Apple Foundation Models und GGUF (Llama).
public enum DocumentNamingPipeline {
    /// Obergrenze gegen Modell-„Roman“; darunter gilt der JSON-Titel als nutzbar (Slug).
    public static let modelTitleWallOfTextWordLimit = 36
    public static let modelTitleWallOfTextCharLimit = 420
    /// Gemeinsames Textlimit für Foundation- und GGUF-Prompts (bisher an beiden Call-Sites 8000).
    public static let excerptCharacterLimit = 8000

    private static let promptDateLock = NSLock()
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

    /// Beginn der Assistentenantwort für Prefilling: zwingt das Modell, das Datum als nächstes zu vervollständigen.
    public static let qwenAssistantJSONDatePrefill = "{\"date\":\""

    /// Erstes vollständiges `{…}` aus dem Rohtext (GGUF schreibt oft endlos weiter).
    public static func truncateToFirstBalancedJSONObject(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let j = extractFirstBalancedJSONObject(from: t) { return j }
        return t
    }

    /// Sobald das erste vollständige `{…}` geschlossen ist, abbrechen (spart Tokens, verhindert Nachplappern).
    public static func ggufShouldStopGeneration(leadIn: String, generatedSuffix: String) -> Bool {
        let full = leadIn + generatedSuffix
        return extractFirstBalancedJSONObject(from: full) != nil
    }

    public static func buildUserPrompt(
        sampleText: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        excerptCharacterLimit: Int = 3000
    ) -> String {
        let modString = formattedPromptDate(fileModificationDate)

        let limit = max(500, excerptCharacterLimit)
        let excerpt = String(sampleText.prefix(limit))
        return """
        ZIEL: Erstelle einen sachlichen Titel aus dem Dokumenttext. Keine Namen von Privatpersonen. Keine Platzhalter.
        SCHEMA: JSON {"date":"YYYY-MM-DD", "archiveTitle":"Typ Thema Jahr Firma"}

        BEISPIELE:
        - Text: Rechnung für Strom 2023 von E.ON an Max... -> {"date":"2023-12-01", "archiveTitle":"Stromrechnung 2023 E.ON"}
        - Text: Bescheid vom Finanzamt München 2024 über Steuern... -> {"date":"2024-02-15", "archiveTitle":"Steuerbescheid 2024 Finanzamt München"}

        DOKUMENTTEXT:
        \(excerpt)

        HILFS-DATUM: \(modString)
        DATEINAME: \(fallbackFilenameStem)
        """
    }

    /// Rohtext des Modells → gleiche Auswertung wie bei Foundation Models.
    public static func analysisPackageFromRawReply(
        raw: String,
        fileModificationDate: Date,
        fallbackFilenameStem: String,
        fallbackTitle: String
    ) -> DocumentAnalysisPackage {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = repairInvalidJSONStringEscapes(extractJSONObject(from: trimmed))
        guard let data = jsonString.data(using: .utf8) else {
            return packageFailure(
                raw: trimmed,
                fileModificationDate: fileModificationDate,
                error: "Could not encode extracted JSON slice as UTF-8.",
                fallbackTitle: fallbackTitle
            )
        }

        let parsed = parseFlexibleRenameResult(data)
            ?? parseLooseGgufJsonRenameResult(trimmed)

        guard let parsed else {
            return packageFailure(
                raw: trimmed,
                fileModificationDate: fileModificationDate,
                error: "JSON decode: could not parse object (see pipeline debug).",
                fallbackTitle: fallbackTitle
            )
        }

        let rawTitle = parsed.generatedTitle
        let wordCount = rawTitle.split(separator: " ", omittingEmptySubsequences: true).count
        let isWallOfText =
            wordCount > modelTitleWallOfTextWordLimit
            || rawTitle.count > modelTitleWallOfTextCharLimit
        let slug = (!rawTitle.isEmpty && !isWallOfText) ? FilenameSanitizer.slugTitle(rawTitle) : ""
        let usedModelTitle = !slug.isEmpty && !isWeakGenericTitle(slug)
        let title = usedModelTitle ? slug : fallbackTitle

        let (docDate, fromDoc) = validatedDocumentDate(iso: parsed.date, fileModificationDate: fileModificationDate)

        let result = DocumentUnderstandingResult(
            title: title,
            documentDate: docDate,
            usedContentDate: fromDoc
        )

        return DocumentAnalysisPackage(
            result: result,
            modelRawReply: trimmed,
            jsonSuggestedTitle: rawTitle.isEmpty ? nil : rawTitle,
            jsonDocumentDateISO: parsed.date,
            jsonDateFromDocument: fromDoc ? true : nil,
            errorStep: nil,
            usedFilenameFallbackForTitle: !usedModelTitle
        )
    }

    public static func packageFailure(
        raw: String,
        fileModificationDate: Date,
        error: String,
        fallbackTitle: String
    ) -> DocumentAnalysisPackage {
        return DocumentAnalysisPackage.titledFallback(
            title: fallbackTitle,
            fileModificationDate: fileModificationDate,
            errorStep: error,
            modelRawReply: raw
        )
    }

    public static func validatedDocumentDate(iso: String?, fileModificationDate: Date) -> (Date, Bool) {
        let trimmed = iso?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count >= 10, trimmed.count <= 32 else {
            return (fileModificationDate, false)
        }
        let head = String(trimmed.prefix(10))
        guard head.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else {
            return (fileModificationDate, false)
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        guard let d = fmt.date(from: head) else {
            return (fileModificationDate, false)
        }
        let y = Calendar(identifier: .gregorian).component(.year, from: d)
        if y < 1990 || y > 2040 {
            return (fileModificationDate, false)
        }
        return (d, true)
    }

    public static func isWeakGenericTitle(_ slug: String) -> Bool {
        let lower = slug.lowercased()
        if ["doc", "document", "pdf", "scan", "file", "untitled", "unknown"].contains(lower) {
            return true
        }
        if lower.count <= 1 {
            return true
        }
        if lower.range(of: "^[0-9\\s\\-:]+$", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    public static func repairInvalidJSONStringEscapes(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        var inString = false
        while i < s.endIndex {
            let c = s[i]
            if !inString {
                if c == "\"" { inString = true }
                out.append(c)
                i = s.index(after: i)
                continue
            }
            if c == "\\" {
                let j = s.index(after: i)
                guard j < s.endIndex else {
                    i = j
                    continue
                }
                let n = s[j]
                switch n {
                case "\"", "\\", "/", "b", "f", "n", "r", "t":
                    out.append("\\")
                    out.append(n)
                    i = s.index(after: j)
                case "u":
                    let hexStart = s.index(after: j)
                    var k = hexStart
                    var digits = 0
                    while k < s.endIndex, digits < 4, isJSONUnicodeHexScalar(s[k]) {
                        digits += 1
                        k = s.index(after: k)
                    }
                    if digits == 4 {
                        out.append("\\u")
                        out.append(contentsOf: s[hexStart..<k])
                        i = k
                    } else {
                        out.append(n)
                        i = j
                    }
                default:
                    out.append(n)
                    i = s.index(after: j)
                }
                continue
            }
            if c == "\"" { inString = false }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    private static func isJSONUnicodeHexScalar(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        let v = s.value
        return (v >= 48 && v <= 57) || (v >= 65 && v <= 70) || (v >= 97 && v <= 102)
    }

    public static func extractJSONObject(from raw: String) -> String {
        let stripped = stripMarkdownCodeFences(from: raw)
        if let balanced = extractFirstBalancedJSONObject(from: stripped) {
            return balanced
        }
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripMarkdownCodeFences(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let nl = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: nl)...])
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fence = s.range(of: "```", options: .backwards) {
            s = String(s[..<fence.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFirstBalancedJSONObject(from s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if escape {
                escape = false
                i = s.index(after: i)
                continue
            }
            if inString {
                if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                i = s.index(after: i)
                continue
            }
            switch c {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(s[start ... i])
                }
            default:
                break
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func parseFlexibleRenameResult(_ data: Data) -> RenameResult? {
        let obj: [String: Any]?
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = root
        } else if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let first = arr.first as? [String: Any] {
            obj = first
        } else {
            obj = nil
        }
        guard let dict = obj else { return nil }

        let date = firstString(dict, keys: [
            "date", "documentDate", "document_date", "documentDateISO", "document_date_iso",
        ])
        var archiveTitle = firstString(dict, keys: [
            "title", "archiveTitle", "archive_title", "suggestedTitle", "suggested_title", "filenameTitle", "filename_title",
        ])
        let trimmedTitle = archiveTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedTitle.isEmpty, let t = firstString(dict, keys: ["text"]), isPlausibleGgufArchiveTitleString(t) {
            archiveTitle = t
        }

        return RenameResult(
            date: date?.trimmingCharacters(in: .whitespacesAndNewlines),
            archiveTitle: archiveTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Wenn das GGUF-Modell kein gültiges JSON liefert, ziehen wir Datum und ggf. Titel per Regex heraus.
    private static func parseLooseGgufJsonRenameResult(_ raw: String) -> RenameResult? {
        let nsLen = (raw as NSString).length
        guard nsLen > 0 else { return nil }
        let full = NSRange(location: 0, length: nsLen)

        var dateStr: String?
        if let re = try? NSRegularExpression(pattern: #""date"\s*:\s*"(\d{4}-\d{2}-\d{2})""#, options: []),
           let m = re.firstMatch(in: raw, options: [], range: full),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: raw) {
            dateStr = String(raw[r])
        }

        var titleStr: String?
        let titleRes = [
            #""title"\s*:\s*"([^"]*)""#,
            #""archiveTitle"\s*:\s*"([^"]*)""#,
            #""archive_title"\s*:\s*"([^"]*)""#,
        ]
        for pat in titleRes {
            guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                  let m = re.firstMatch(in: raw, options: [], range: full),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: raw) else { continue }
            let t = String(raw[r])
            if isPlausibleGgufArchiveTitleString(t) {
                titleStr = t
                break
            }
        }
        if titleStr == nil,
           let re = try? NSRegularExpression(pattern: #""text"\s*:\s*"([^"]*)""#, options: .caseInsensitive),
           let m = re.firstMatch(in: raw, options: [], range: full),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: raw) {
            let t = String(raw[r])
            if isPlausibleGgufArchiveTitleString(t) {
                titleStr = t
            }
        }

        let tTrim = titleStr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard dateStr != nil || !tTrim.isEmpty else { return nil }
        return RenameResult(
            date: dateStr?.trimmingCharacters(in: .whitespacesAndNewlines),
            archiveTitle: tTrim.isEmpty ? nil : titleStr?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func isPlausibleGgufArchiveTitleString(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4, t.count <= 400 else { return false }
        let lower = t.lowercased()
        let forbidden = [
            "nutze ausschließlich", "nutze ausschliesslich", "ausschließlich den inhalt",
            "anweisung", "text-anfang", "text-ende", "vervollständig", "vervollstandig",
            "zwischen den zeilen", "keine sätze", "keine satze", "json-zeile", "json zeile",
        ]
        for f in forbidden {
            if lower.contains(f) { return false }
        }
        return true
    }

    private static func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let v = dict[key] else { continue }
            if v is NSNull { continue }
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
        }
        return nil
    }
}
