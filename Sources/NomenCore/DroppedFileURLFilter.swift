import Foundation

/// Nimmt nur echte `file:`-URLs — keine Tilde-Pfade und keine freien POSIX-Strings.
/// Die URL wird nicht standardisiert, damit ein Security Scope vom Drop erhalten bleibt.
public enum DroppedFileURLFilter {
    public static func accept(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        guard !url.path.isEmpty else { return nil }
        return url
    }

    /// Pasteboard-`Data`: Bookmark, `NSURL`-Bytes oder `file://`-String — kein Rohpfad.
    public static func acceptPasteboardData(_ data: Data) -> URL? {
        var stale = false
        if let bookmark = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), let accepted = accept(bookmark) {
            return accepted
        }
        if let url = URL(dataRepresentation: data, relativeTo: nil), let accepted = accept(url) {
            return accepted
        }
        if let s = String(data: data, encoding: .utf8) {
            return acceptFileURLString(s)
        }
        return nil
    }

    /// Nur `file://…`, nicht `/Users/…` oder `~/Documents`.
    public static func acceptFileURLString(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard let url = URL(string: trimmed) else { return nil }
        return accept(url)
    }
}
