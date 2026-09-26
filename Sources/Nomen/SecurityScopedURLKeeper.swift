import Foundation

/// Hält Security-Scoped-Zugriff für importierte Dateien über Analyse und Rename hinweg.
///
/// Open Panel / Drag-Drop liefern in der App-Sandbox nur Scope auf die einzelne Datei.
/// Start/Stop pro Kurzoperation (OCR, Rename) ist fehleranfällig; deshalb bleibt der Zugriff
/// aktiv, solange die Datei in der Sitzung ist.
@MainActor
final class SecurityScopedURLKeeper {
    private var retained: [String: URL] = [:]

    func retain(_ urls: [URL]) {
        for url in urls {
            let key = Self.key(url)
            guard retained[key] == nil else { continue }
            if url.startAccessingSecurityScopedResource() {
                retained[key] = url
            }
        }
    }

    func release(paths: some Sequence<String>) {
        for path in paths {
            let key = Self.key(URL(fileURLWithPath: path))
            if let url = retained.removeValue(forKey: key) {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    func releaseAll() {
        for url in retained.values {
            url.stopAccessingSecurityScopedResource()
        }
        retained.removeAll()
    }

    /// Nach erfolgreichem Rename: `didMoveTo` hat den Scope auf den neuen Namen übertragen.
    func noteRenamed(from old: URL, to new: URL) {
        let oldKey = Self.key(old)
        guard retained.removeValue(forKey: oldKey) != nil else { return }
        retained[Self.key(new)] = new
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
