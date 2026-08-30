import Foundation

public enum FileRenameError: LocalizedError {
    case destinationEscapesDirectory
    case invalidFileName

    public var errorDescription: String? {
        switch self {
        case .destinationEscapesDirectory:
            return "Der Zielname liegt außerhalb des Quellordners."
        case .invalidFileName:
            return "Der vorgeschlagene Dateiname ist ungültig."
        }
    }
}

/// Dateisystem-Operationen für Vorschau-Kollisionen und das eigentliche Umbenennen.
public enum FileRenameOperations {
    public static func uniquifyFilename(
        desiredName: String,
        directory: URL,
        ignoreIfSameAs source: URL,
        fileManager: FileManager = .default
    ) -> String {
        let safeName = ((try? confinedFileName(desiredName)) ?? FilenameSanitizer.archiveFallbackLiteral)
        let target: URL
        do {
            target = try confinedDestination(directory: directory, fileName: safeName)
        } catch {
            return FilenameSanitizer.archiveFallbackLiteral
        }
        if target.path == source.path {
            return safeName
        }
        if !fileManager.fileExists(atPath: target.path) {
            return safeName
        }

        let ns = safeName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension

        var i = 2
        while i < 10_000 {
            let candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            guard let url = try? confinedDestination(directory: directory, fileName: candidate) else {
                i += 1
                continue
            }
            if !fileManager.fileExists(atPath: url.path) {
                return candidate
            }
            i += 1
        }
        return safeName
    }

    /// Verschiebt `source` auf einen kollisionsfreien Namen. Unverändert, wenn Quelle und Ziel identisch sind.
    public static func renameIfNeeded(
        source: URL,
        desiredName: String,
        fileManager: FileManager = .default
    ) throws -> (finalURL: URL, finalName: String) {
        let directory = source.deletingLastPathComponent()
        var unique = uniquifyFilename(
            desiredName: desiredName,
            directory: directory,
            ignoreIfSameAs: source,
            fileManager: fileManager
        )
        var finalURL = try confinedDestination(directory: directory, fileName: unique)
        if finalURL.path == source.path {
            return (finalURL, unique)
        }
        do {
            try fileManager.moveItem(at: source, to: finalURL)
        } catch {
            unique = uniquifyFilename(
                desiredName: desiredName,
                directory: directory,
                ignoreIfSameAs: source,
                fileManager: fileManager
            )
            finalURL = try confinedDestination(directory: directory, fileName: unique)
            if finalURL.path != source.path {
                try fileManager.moveItem(at: source, to: finalURL)
            }
        }
        return (finalURL, unique)
    }

    public static func confinedFileName(_ desiredName: String) throws -> String {
        let name = (desiredName as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name == desiredName else {
            throw FileRenameError.invalidFileName
        }
        if name.contains("/") || name.contains("\\") || name.contains("\0") {
            throw FileRenameError.invalidFileName
        }
        return name
    }

    public static func confinedDestination(directory: URL, fileName: String) throws -> URL {
        let name = try confinedFileName(fileName)
        let dir = directory.standardizedFileURL
        let dest = dir.appendingPathComponent(name, isDirectory: false).standardizedFileURL
        guard dest.deletingLastPathComponent().standardizedFileURL.path == dir.path else {
            throw FileRenameError.destinationEscapesDirectory
        }
        return dest
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
