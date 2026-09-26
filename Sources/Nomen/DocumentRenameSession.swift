import Foundation
import NomenCore

/// Führt einen Umbenennungs-Lauf inkl. Feedback-Timing aus.
/// ViewModel bleibt für Task-Lifecycle und `clear()` zuständig.
@MainActor
enum DocumentRenameSession {
    struct Outcome {
        var rows: [RenamePreviewRow]
        var lastInputURLs: [URL]
        var shouldClearList: Bool
    }

    enum Event {
        case feedback(RenameFeedbackPhase)
        case rows([RenamePreviewRow])
        case row(at: Int, RenamePreviewRow)
    }

    private struct IOResult: Sendable {
        var success: Bool
        var finalURL: URL
        var targetName: String
        var errorDescription: String?
    }

    static func interRenameDelay(total: Int) -> Duration? {
        switch total {
        case 1...6: return .milliseconds(50)
        case 7...25: return .milliseconds(16)
        default: return nil
        }
    }

    /// Läuft den Rename-Loop. Rückgabe `nil` bei Abbruch.
    /// `shouldClearList` ist nur bei vollständigem Erfolg und Preference gesetzt.
    static func run(
        rows: [RenamePreviewRow],
        lastInputURLs: [URL],
        indices: [Int],
        renamedEntireList: Bool,
        clearListAfterSuccessfulRename: Bool,
        renamedStatus: String,
        renameErrorMessage: (String) -> String,
        emit: (Event) -> Void
    ) async -> Outcome? {
        let total = indices.count
        guard total > 0 else { return nil }

        emit(.feedback(.working(done: 0, total: total)))
        if total <= 8 {
            try? await Task.sleep(for: .milliseconds(60))
        }

        var updated = rows
        var urls = lastInputURLs
        var successCount = 0
        var failureCount = 0
        let stepDelay = interRenameDelay(total: total)

        for (step, idx) in indices.enumerated() {
            if Task.isCancelled {
                emit(.rows(updated))
                emit(.feedback(.idle))
                return nil
            }
            guard updated.indices.contains(idx) else { continue }

            let source = updated[idx].sourceURL
            let desiredName = updated[idx].proposedName
            let io = await Task.detached(priority: .userInitiated) {
                renameOnBackground(source: source, desiredName: desiredName)
            }.value

            if io.success {
                successCount += 1
                if io.finalURL.path != source.path {
                    updated[idx].sourceURL = io.finalURL
                    if let j = urls.firstIndex(where: { $0.path == source.path }) {
                        urls[j] = io.finalURL
                    }
                }
                updated[idx].proposedName = io.targetName
                updated[idx].originalName = io.targetName
                updated[idx].statusMessage = renamedStatus
            } else {
                failureCount += 1
                updated[idx].statusMessage = renameErrorMessage(io.errorDescription ?? "")
            }
            emit(.row(at: idx, updated[idx]))
            emit(.feedback(.working(done: step + 1, total: total)))
            if let stepDelay {
                try? await Task.sleep(for: stepDelay)
            }
        }

        urls = updated.map(\.sourceURL)

        if successCount == 0, failureCount > 0 {
            emit(.feedback(.outcome(
                kind: .allFailed,
                renamedCount: 0,
                renamedEntireList: renamedEntireList
            )))
            try? await Task.sleep(for: .milliseconds(700))
            emit(.feedback(.idle))
            return Outcome(rows: updated, lastInputURLs: urls, shouldClearList: false)
        }

        if successCount > 0, failureCount == 0 {
            emit(.feedback(.outcome(
                kind: .success,
                renamedCount: successCount,
                renamedEntireList: renamedEntireList
            )))
            try? await Task.sleep(for: .milliseconds(880))
            let shouldClear = clearListAfterSuccessfulRename && renamedEntireList
            if !shouldClear {
                emit(.feedback(.idle))
            }
            return Outcome(rows: updated, lastInputURLs: urls, shouldClearList: shouldClear)
        }

        emit(.feedback(.outcome(
            kind: .partialFailure,
            renamedCount: successCount,
            renamedEntireList: renamedEntireList
        )))
        try? await Task.sleep(for: .milliseconds(900))
        emit(.feedback(.idle))
        return Outcome(rows: updated, lastInputURLs: urls, shouldClearList: false)
    }

    nonisolated private static func renameOnBackground(source: URL, desiredName: String) -> IOResult {
        let granted = source.startAccessingSecurityScopedResource()
        do {
            let (finalURL, targetName) = try FileRenameOperations.renameIfNeeded(
                source: source,
                desiredName: desiredName
            )
            if granted {
                finalURL.stopAccessingSecurityScopedResource()
            }
            return IOResult(
                success: true,
                finalURL: finalURL,
                targetName: targetName,
                errorDescription: nil
            )
        } catch {
            if granted {
                source.stopAccessingSecurityScopedResource()
            }
            return IOResult(
                success: false,
                finalURL: source,
                targetName: desiredName,
                errorDescription: error.localizedDescription
            )
        }
    }
}
