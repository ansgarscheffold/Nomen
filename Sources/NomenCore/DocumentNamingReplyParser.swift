import Foundation

/// JSON-Extraktion, Repair und Auswertung von Modell-Rohantworten.
public enum DocumentNamingReplyParser {
    /// Obergrenze gegen Modell-„Roman“; darunter gilt der JSON-Titel als nutzbar (Slug).
    public static let modelTitleWallOfTextWordLimit = 36
    public static let modelTitleWallOfTextCharLimit = 420

    private static let looseDateJSONRegex = try! NSRegularExpression(
        pattern: #""date"\s*:\s*"(\d{4}-\d{2}-\d{2})""#
    )
    private static let looseTitleJSONRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #""title"\s*:\s*"([^"]*)""#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #""archiveTitle"\s*:\s*"([^"]*)""#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #""archive_title"\s*:\s*"([^"]*)""#, options: .caseInsensitive),
    ]
    private static let looseTextJSONRegex = try! NSRegularExpression(
        pattern: #""text"\s*:\s*"([^"]*)""#,
        options: .caseInsensitive
    )

    /// Erstes vollständiges `{…}` aus dem Rohtext (GGUF schreibt oft endlos weiter).
    public static func truncateToFirstBalancedJSONObject(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let j = extractFirstBalancedJSONObject(from: t) { return j }
        return t
    }

    /// Sobald das erste vollständige `{…}` geschlossen ist, abbrechen (spart Tokens, verhindert Nachplappern).
    public static func ggufShouldStopGeneration(leadIn: String, generatedSuffix: String) -> Bool {
        guard generatedSuffix.contains("}") else { return false }
        var tracker = BalancedJSONObjectTracker()
        return tracker.consume(leadIn) || tracker.consume(generatedSuffix)
    }

    /// Inkrementeller Brace-/String-Scanner für den GGUF-Decode-Hot-Path (O(Δ) statt Full-Rescan).
    public struct BalancedJSONObjectTracker: Sendable {
        private var depth = 0
        private var inString = false
        private var escape = false
        private var started = false
        private var complete = false

        public init() {}

        /// Füttert neue Zeichen; `true`, sobald das erste balancierte `{…}` geschlossen ist.
        public mutating func consume(_ s: String) -> Bool {
            guard !complete else { return true }
            for c in s {
                if feed(c) {
                    complete = true
                    return true
                }
            }
            return false
        }

        private mutating func feed(_ c: Character) -> Bool {
            if escape {
                escape = false
                return false
            }
            if inString {
                if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                return false
            }
            switch c {
            case "\"":
                inString = true
            case "{":
                depth += 1
                started = true
            case "}":
                guard started else { return false }
                depth -= 1
                if depth == 0 {
                    return true
                }
            default:
                break
            }
            return false
        }
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

        let (docDate, fromDoc) = DocumentNamingDateValidation.validatedDocumentDate(
            iso: parsed.date,
            fileModificationDate: fileModificationDate
        )

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

    public static func isWeakGenericTitle(_ slug: String) -> Bool {
        let lower = slug.lowercased()
        if ["doc", "document", "pdf", "scan", "file", "untitled", "unknown"].contains(lower) {
            return true
        }
        if lower.count <= 1 {
            return true
        }
        if lower.allSatisfy({ $0.isNumber || $0.isWhitespace || $0 == "-" || $0 == ":" }) {
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

    public static func extractJSONObject(from raw: String) -> String {
        let stripped = stripMarkdownCodeFences(from: raw)
        if let balanced = extractFirstBalancedJSONObject(from: stripped) {
            return balanced
        }
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isJSONUnicodeHexScalar(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        let v = s.value
        return (v >= 48 && v <= 57) || (v >= 65 && v <= 70) || (v >= 97 && v <= 102)
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
        if let m = looseDateJSONRegex.firstMatch(in: raw, options: [], range: full),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: raw) {
            dateStr = String(raw[r])
        }

        var titleStr: String?
        for re in looseTitleJSONRegexes {
            guard let m = re.firstMatch(in: raw, options: [], range: full),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: raw) else { continue }
            let t = String(raw[r])
            if isPlausibleGgufArchiveTitleString(t) {
                titleStr = t
                break
            }
        }
        if titleStr == nil,
           let m = looseTextJSONRegex.firstMatch(in: raw, options: [], range: full),
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
