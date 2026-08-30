import Foundation

/// Nimmt nur echte `file:`-URLs — keine Tilde-Pfade und keine freien Strings.
public enum DroppedFileURLFilter {
    public static func accept(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let standardized = url.standardizedFileURL
        guard !standardized.path.isEmpty else { return nil }
        return standardized
    }
}
