import AppKit

/// Fordert per NSOpenPanel Schreibzugriff auf Elternordner an.
/// In der App-Sandbox reicht Datei-Scope nicht zum Umbenennen — der Ordner muss freigegeben sein.
@MainActor
enum FolderAccessGrant {
    /// `true`, wenn für alle Ordner Zugriff besteht (oder soeben erteilt wurde).
    static func ensureAccess(
        toParentDirectoriesOf fileURLs: [URL],
        keeper: SecurityScopedURLKeeper,
        title: String,
        messageForFolder: (String) -> String,
        prompt: String
    ) async -> Bool {
        let directories = uniqueParentDirectories(of: fileURLs)
        for directory in directories {
            if keeper.hasDirectoryAccess(covering: directory) { continue }
            if keeper.restoreDirectoryAccess(for: directory) { continue }

            let granted = await presentDirectoryPanel(
                targeting: directory,
                title: title,
                message: messageForFolder(directory.lastPathComponent),
                prompt: prompt
            )
            guard let granted else { return false }
            // Muss derselbe Ordner sein (sonst hätte der User etwas anderes gewählt).
            let grantedKey = granted.standardizedFileURL.path
            let expectedKey = directory.standardizedFileURL.path
            guard grantedKey == expectedKey else {
                // User hat einen anderen Ordner gewählt — trotzdem behalten, aber für diesen Lauf ablehnen.
                keeper.retainDirectory(granted)
                return false
            }
            keeper.retainDirectory(granted)
        }
        return true
    }

    private static func uniqueParentDirectories(of fileURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var dirs: [URL] = []
        for file in fileURLs {
            let dir = file.deletingLastPathComponent().standardizedFileURL
            if seen.insert(dir.path).inserted {
                dirs.append(dir)
            }
        }
        return dirs
    }

    private static func presentDirectoryPanel(
        targeting directory: URL,
        title: String,
        message: String,
        prompt: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.directoryURL = directory
            panel.message = message
            panel.prompt = prompt
            panel.title = title

            // Sheet auf dem Key-Window, falls vorhanden — sonst modal.
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            } else {
                let response = panel.runModal()
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
