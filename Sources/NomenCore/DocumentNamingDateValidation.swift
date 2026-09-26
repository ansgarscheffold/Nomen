import Foundation

/// Validierung von Modell-Datumsangaben (ISO `YYYY-MM-DD`) gegen Datei-Metadaten.
public enum DocumentNamingDateValidation {
    private static let gmtGregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    public static func validatedDocumentDate(iso: String?, fileModificationDate: Date) -> (Date, Bool) {
        let trimmed = iso?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count >= 10, trimmed.count <= 32 else {
            return (fileModificationDate, false)
        }
        let head = String(trimmed.prefix(10))
        guard isYearMonthDay(head) else {
            return (fileModificationDate, false)
        }
        guard let d = dateFromYearMonthDay(head) else {
            return (fileModificationDate, false)
        }
        let y = gmtGregorian.component(.year, from: d)
        if y < 1990 || y > 2040 {
            return (fileModificationDate, false)
        }
        return (d, true)
    }

    /// `YYYY-MM-DD` without compiling a regex on every model reply.
    private static func isYearMonthDay(_ s: String) -> Bool {
        let utf8 = s.utf8
        guard utf8.count == 10 else { return false }
        var i = utf8.startIndex
        func digits(_ count: Int) -> Bool {
            for _ in 0..<count {
                guard i < utf8.endIndex else { return false }
                let v = utf8[i]
                guard v >= 48, v <= 57 else { return false }
                i = utf8.index(after: i)
            }
            return true
        }
        func dash() -> Bool {
            guard i < utf8.endIndex, utf8[i] == 45 else { return false }
            i = utf8.index(after: i)
            return true
        }
        return digits(4) && dash() && digits(2) && dash() && digits(2) && i == utf8.endIndex
    }

    private static func dateFromYearMonthDay(_ head: String) -> Date? {
        guard let y = Int(head.prefix(4)),
              let m = Int(head.dropFirst(5).prefix(2)),
              let d = Int(head.dropFirst(8).prefix(2)) else {
            return nil
        }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        return gmtGregorian.date(from: comps)
    }
}
