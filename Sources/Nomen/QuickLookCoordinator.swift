import AppKit
import Foundation
import QuickLookUI
import NomenCore

/// Finder-ähnliche Quick Look (Space) für ausgewählte Datei-URLs.
/// Hält Security-Scoped-Zugriff für Sandbox-Dateien bis zum Schließen des Panels.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, ObservableObject {
    private var urls: [URL] = []
    private var securityScopedURLs: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as QLPreviewItem
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        stopSecurityScopedAccess()
    }

    private func stopSecurityScopedAccess() {
        for u in securityScopedURLs {
            u.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }

    @MainActor
    func show(urls newURLs: [URL]) {
        stopSecurityScopedAccess()
        let filtered = newURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !filtered.isEmpty else { return }

        for u in filtered {
            if u.startAccessingSecurityScopedResource() {
                securityScopedURLs.append(u)
            }
        }
        urls = filtered

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
        panel.refreshCurrentPreviewItem()
    }
}
