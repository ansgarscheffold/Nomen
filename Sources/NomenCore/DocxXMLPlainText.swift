import Foundation

/// Lineares Herausziehen von `<w:t>`-Läufen — kein gieriger Regex auf dem gesamten XML.
public enum DocxXMLPlainText {
    public static let defaultCharacterLimit = 8_000

    public static func extract(from xml: String, characterLimit: Int = defaultCharacterLimit) -> String {
        let limit = max(1, characterLimit)
        var parts: [String] = []
        parts.reserveCapacity(64)
        var total = 0
        var searchStart = xml.startIndex

        while total < limit, searchStart < xml.endIndex {
            guard let open = xml.range(of: "<w:t", range: searchStart..<xml.endIndex) else { break }
            let afterOpen = open.upperBound
            guard afterOpen < xml.endIndex, let tagEnd = xml[afterOpen...].firstIndex(of: ">") else { break }
            let contentStart = xml.index(after: tagEnd)
            guard contentStart < xml.endIndex else { break }
            guard let close = xml.range(of: "</w:t>", range: contentStart..<xml.endIndex) else {
                searchStart = contentStart
                continue
            }
            let piece = unescapeMinimalXMLEntities(String(xml[contentStart..<close.lowerBound]))
            parts.append(piece)
            total += piece.count + 1
            searchStart = close.upperBound
        }

        let joined = parts.joined(separator: " ")
        if joined.count <= limit { return joined }
        return String(joined.prefix(limit))
    }

    private static func unescapeMinimalXMLEntities(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
