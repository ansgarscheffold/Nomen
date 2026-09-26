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
        if sameFile(source, target) {
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

    /// Benennt `source` kollisionsfrei um (gleicher Ordner). Unverändert, wenn der Name schon passt.
    ///
    /// Erfordert Schreibzugriff auf den Elternordner (App-Sandbox: Ordner per Open Panel /
    /// Drag-Drop freigeben). Dann `moveItem` über NSFileCoordinator.
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
        if source.lastPathComponent == unique {
            return (source, unique)
        }

        do {
            return try renameInPlace(source: source, newFileName: unique)
        } catch {
            unique = uniquifyFilename(
                desiredName: desiredName,
                directory: directory,
                ignoreIfSameAs: source,
                fileManager: fileManager
            )
            if source.lastPathComponent == unique {
                return (source, unique)
            }
            return try renameInPlace(source: source, newFileName: unique)
        }
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

    /// Gleicher Eintrag trotz unterschiedlicher URL-Normalisierung (`standardizedFileURL` o.ä.).
    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    private static func renameInPlace(source: URL, newFileName: String) throws -> (finalURL: URL, finalName: String) {
        let name = try confinedFileName(newFileName)
        let destination = source.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false)
        // POSIX-Rename braucht Schreibrecht auf den Elternordner. In der Sandbox liefert
        // Open/Drop von Einzeldateien nur Datei-Scope — deshalb muss die UI vorher
        // Ordnerzugriff per NSOpenPanel holen (`FolderAccessGrant` + `SecurityScopedURLKeeper`).
        // Mit Ordner-Scope ist `moveItem` der zuverlässige Weg.
        var coordinationError: NSError?
        var renameError: Error?
        var resultURL: URL?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: source,
            options: .forMoving,
            writingItemAt: destination,
            options: [],
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            do {
                try FileManager.default.moveItem(at: coordinatedSource, to: coordinatedDestination)
                coordinator.item(at: coordinatedSource, didMoveTo: coordinatedDestination)
                resultURL = coordinatedDestination
            } catch {
                renameError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let renameError {
            throw renameError
        }
        guard let resultURL else {
            throw FileRenameError.invalidFileName
        }
        return (resultURL, name)
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
