import Foundation

/// Filesystem-safe title and pattern-based filename assembly (not document understanding).
public enum FilenameFormatting {
    public static func formatFilename(
        schema: DateNameSchema,
        title: String,
        date: Date,
        originalExtension: String
    ) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1

        let yy = String(format: "%02d", y % 100)
        let mm = String(format: "%02d", m)
        let dd = String(format: "%02d", d)

        var cleanedTitle = FilenameSanitizer.slugTitle(title)
        cleanedTitle = stripRedundantDatePrefix(
            from: cleanedTitle,
            schema: schema,
            year: y,
            monthPadded: mm,
            day: d,
            dayPadded: dd,
            yearTwoDigit: yy
        )
        if cleanedTitle.isEmpty {
            cleanedTitle = FilenameSanitizer.archiveFallbackLiteral
        }

        let base: String
        switch schema {
        case .yearMonthTitle:
            base = "\(y) \(mm) \(cleanedTitle)"
        case .compactDateTitle:
            base = "\(yy)\(mm)\(dd) \(cleanedTitle)"
        case .titleOnly:
            base = cleanedTitle
        }
        let ext = originalExtension.lowercased()
        if ext.isEmpty {
            return base
        }
        return "\(base).\(ext)"
    }

    /// When the model (or filename stem) repeats the same calendar prefix the schema will add, drop it to avoid `2026 04 2026 04 10 Doc`.
    private static func stripRedundantDatePrefix(
        from cleanedTitle: String,
        schema: DateNameSchema,
        year: Int,
        monthPadded: String,
        day: Int,
        dayPadded: String,
        yearTwoDigit: String
    ) -> String {
        var t = cleanedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        switch schema {
        case .yearMonthTitle:
            let ym = "\(year) \(monthPadded) "
            while t.hasPrefix(ym) {
                t = String(t.dropFirst(ym.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            t = stripLeadingDayTimeNoiseIfMatchesDocumentDay(t, day: day, dayPadded: dayPadded)
        case .compactDateTitle:
            let compact = "\(yearTwoDigit)\(monthPadded)\(dayPadded) "
            if t.hasPrefix(compact) {
                t = String(t.dropFirst(compact.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let ymd = "\(year) \(monthPadded) \(dayPadded) "
            while t.hasPrefix(ymd) {
                t = String(t.dropFirst(ymd.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .titleOnly:
            break
        }
        return t
    }

    /// Turns `10 01 36 Doc` (day + time from an old filename) into `Doc` when `10` matches the document day.
    private static func stripLeadingDayTimeNoiseIfMatchesDocumentDay(
        _ title: String,
        day: Int,
        dayPadded: String
    ) -> String {
        let parts = title.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return title }
        let d0 = parts[0]
        let dayMatches = d0 == dayPadded || d0 == String(day)
        guard dayMatches else { return title }
        guard parts[1].allSatisfy(\.isNumber), parts[2].allSatisfy(\.isNumber) else { return title }
        guard let h = Int(parts[1]), let m = Int(parts[2]) else { return title }
        guard h >= 0, h < 24, m >= 0, m < 60 else { return title }
        return parts.dropFirst(3).joined(separator: " ")
    }
}

public enum FilenameSanitizer {
    public static let archiveFallbackLiteral = "Document"

    private static let leadingYMDTime = try! NSRegularExpression(
        pattern: #"^\d{4} \d{2} \d{2}(\s+\d+)*\s*"#
    )
    private static let leadingYYYYMMDD = try! NSRegularExpression(pattern: #"^\d{8} "#)
    private static let leadingYYMMDD = try! NSRegularExpression(pattern: #"^\d{6} "#)
    private static let leadingYYYYMM = try! NSRegularExpression(pattern: #"^\d{4} \d{2} "#)
    private static let leadingYYMM = try! NSRegularExpression(pattern: #"^\d{2} \d{2} "#)
    private static let amPmToken = try! NSRegularExpression(
        pattern: #"^\d+(am|pm)$"#,
        options: .caseInsensitive
    )

    /// Dateiname-Stamm → Archiv-Titel, wenn das Modell keinen brauchbaren Titel liefert.
    public static func archiveFallbackTitle(fromFilenameStem stem: String) -> String {
        let slug = cleanStemForTitle(stem)
        return slug.isEmpty ? archiveFallbackLiteral : slug
    }

    /// Strips date/time prefixes and noise tokens from a raw filename stem so the
    /// fallback title doesn't duplicate the date the naming schema will prepend,
    /// and doesn't include case numbers, timestamps, or other non-semantic tokens.
    ///
    /// Examples:
    ///   "231215 Hausratversicherung"              → "Hausratversicherung"
    ///   "2026-04-10 01-33 - Doc"                 → "Doc"
    ///   "Apple Support Case 102866598713 11_4_2026_1_24pm" → "Apple Support Case"
    ///   "23 05 Gartensofa"                        → "Gartensofa"
    public static func cleanStemForTitle(_ stem: String) -> String {
        var s = slugTitle(stem)

        s = stripLeadingMatch(leadingYMDTime, from: s)
        s = stripLeadingMatch(leadingYYYYMMDD, from: s)
        s = stripLeadingMatch(leadingYYMMDD, from: s)
        s = stripLeadingMatch(leadingYYYYMM, from: s)
        s = stripLeadingMatch(leadingYYMM, from: s)

        // Keep only tokens that contain at least one letter — pure digit strings
        // (e.g. "102866598713", "11", "4") and time suffixes ("24pm", "1am")
        // carry no archival meaning in a filename title.
        let filtered = s
            .split(separator: " ", omittingEmptySubsequences: true)
            .filter { token in
                let t = String(token)
                if t.allSatisfy(\.isNumber) { return false }
                let nsLen = (t as NSString).length
                if amPmToken.firstMatch(in: t, options: [], range: NSRange(location: 0, length: nsLen)) != nil {
                    return false
                }
                return true
            }
            .joined(separator: " ")

        return filtered.isEmpty ? s : filtered
    }

    private static func stripLeadingMatch(_ regex: NSRegularExpression, from s: String) -> String {
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: s, options: [], range: full),
              match.range.location == 0,
              match.range.length > 0 else {
            return s
        }
        return ns.substring(from: match.range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func slugTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Kein diacriticInsensitive-Folding: Umlaute (äöü) und ß sollen in Dateinamen erhalten bleiben;
        // APFS/HFS+ nutzen UTF-8. Früheres Folding hat sie zu a/o/u verflacht.
        var result = ""
        result.reserveCapacity(trimmed.count)
        var lastWasSpace = false
        for ch in trimmed {
            if ch.isLetter || ch.isNumber {
                result.append(ch)
                lastWasSpace = false
            } else if ch == " " || ch == "-" || ch == "_" {
                if !lastWasSpace, !result.isEmpty {
                    result.append(" ")
                    lastWasSpace = true
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
