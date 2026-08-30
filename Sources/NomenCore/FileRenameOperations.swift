import Foundation

/// Dateisystem-Operationen für Vorschau-Kollisionen und das eigentliche Umbenennen.
public enum FileRenameOperations {
    public static func uniquifyFilename(
        desiredName: String,
        directory: URL,
        ignoreIfSameAs source: URL,
        fileManager: FileManager = .default
    ) -> String {
        let target = directory.appendingPathComponent(desiredName)
        if target.path == source.path {
            return desiredName
        }
        if !fileManager.fileExists(atPath: target.path) {
            return desiredName
        }

        let ns = desiredName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension

        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let url = directory.appendingPathComponent(candidate)
            if !fileManager.fileExists(atPath: url.path) {
                return candidate
            }
            i += 1
        }
    }

    /// Verschiebt `source` auf einen kollisionsfreien Namen. Unverändert, wenn Quelle und Ziel identisch sind.
    public static func renameIfNeeded(
        source: URL,
        desiredName: String,
        fileManager: FileManager = .default
    ) throws -> (finalURL: URL, finalName: String) {
        let directory = source.deletingLastPathComponent()
        let unique = uniquifyFilename(
            desiredName: desiredName,
            directory: directory,
            ignoreIfSameAs: source,
            fileManager: fileManager
        )
        let finalURL = directory.appendingPathComponent(unique)
        if finalURL.path != source.path {
            try fileManager.moveItem(at: source, to: finalURL)
        }
        return (finalURL, unique)
    }
}

public enum SecurityScopedResource {
    @MainActor
    public static func accessing<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }
}
