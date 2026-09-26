import Foundation
import NomenCore

/// Hält Security-Scoped-Zugriff für Dateien und — entscheidend für Rename —
/// für Elternordner (Sandbox: Umbenennen braucht Schreibrecht auf den Ordner).
@MainActor
final class SecurityScopedURLKeeper {
    private static let bookmarkDefaultsKey = "nomen.folderSecurityBookmarks"

    private var retainedFiles: [String: URL] = [:]
    private var retainedDirectories: [String: URL] = [:]

    init() {
        restorePersistedDirectoryBookmarks()
    }

    func retain(_ urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                retainDirectory(url)
                continue
            }
            let key = Self.key(url)
            guard retainedFiles[key] == nil else { continue }
            if url.startAccessingSecurityScopedResource() {
                retainedFiles[key] = url
            }
        }
    }

    func retainDirectory(_ url: URL) {
        let dir = url.standardizedFileURL
        let key = Self.key(dir)
        if retainedDirectories[key] != nil { return }
        if dir.startAccessingSecurityScopedResource() {
            retainedDirectories[key] = dir
            persistBookmark(for: dir)
        }
    }

    func hasDirectoryAccess(covering fileOrDirectory: URL) -> Bool {
        let dirKey = Self.key(parentDirectory(of: fileOrDirectory))
        return retainedDirectories[dirKey] != nil
    }

    /// Versucht gespeicherten Bookmark für diesen Ordner zu aktivieren.
    @discardableResult
    func restoreDirectoryAccess(for directory: URL) -> Bool {
        let key = Self.key(directory)
        if retainedDirectories[key] != nil { return true }
        guard let data = loadBookmarkMap()[key] else { return false }
        return activateDirectoryBookmark(data)
    }

    func release(paths: some Sequence<String>) {
        for path in paths {
            let key = Self.key(URL(fileURLWithPath: path))
            if let url = retainedFiles.removeValue(forKey: key) {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    func releaseAll() {
        for url in retainedFiles.values {
            url.stopAccessingSecurityScopedResource()
        }
        retainedFiles.removeAll()
        // Ordner-Scopes und Bookmarks bleiben über Sitzungen erhalten (Rename braucht sie erneut).
    }

    func noteRenamed(from old: URL, to new: URL) {
        let oldKey = Self.key(old)
        guard retainedFiles.removeValue(forKey: oldKey) != nil else { return }
        retainedFiles[Self.key(new)] = new
    }

    /// Unterstützte Dateien in einem Ordner (nicht rekursiv).
    static func supportedFiles(inDirectory directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return false
            }
            return SupportedDocumentFormat.isSupported(url: url)
        }
    }

    private func parentDirectory(of url: URL) -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return url.standardizedFileURL
        }
        return url.deletingLastPathComponent().standardizedFileURL
    }

    private func restorePersistedDirectoryBookmarks() {
        for data in loadBookmarkMap().values {
            _ = activateDirectoryBookmark(data)
        }
    }

    private func activateDirectoryBookmark(_ data: Data) -> Bool {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return false }
        let standardized = url.standardizedFileURL
        let key = Self.key(standardized)
        if retainedDirectories[key] != nil { return true }
        guard standardized.startAccessingSecurityScopedResource() else { return false }
        retainedDirectories[key] = standardized
        if stale {
            persistBookmark(for: standardized)
        }
        return true
    }

    private func persistBookmark(for directory: URL) {
        guard let data = try? directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        var map = loadBookmarkMap()
        map[Self.key(directory)] = data
        saveBookmarkMap(map)
    }

    private func loadBookmarkMap() -> [String: Data] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.bookmarkDefaultsKey) else {
            return [:]
        }
        var result: [String: Data] = [:]
        result.reserveCapacity(raw.count)
        for (key, value) in raw {
            if let data = value as? Data {
                result[key] = data
            }
        }
        return result
    }

    private func saveBookmarkMap(_ map: [String: Data]) {
        UserDefaults.standard.set(map, forKey: Self.bookmarkDefaultsKey)
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
