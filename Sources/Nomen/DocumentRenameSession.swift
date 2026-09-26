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

            if applyRename(
                at: idx,
                updated: &updated,
                lastInputURLs: &urls,
                renamedStatus: renamedStatus,
                renameErrorMessage: renameErrorMessage
            ) {
                successCount += 1
            } else {
                failureCount += 1
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

    private static func applyRename(
        at index: Int,
        updated: inout [RenamePreviewRow],
        lastInputURLs: inout [URL],
        renamedStatus: String,
        renameErrorMessage: (String) -> String
    ) -> Bool {
        let source = updated[index].sourceURL
        let granted = source.startAccessingSecurityScopedResource()
        do {
            let (finalURL, targetName) = try FileRenameOperations.renameIfNeeded(
                source: source,
                desiredName: updated[index].proposedName
            )
            if granted {
                finalURL.stopAccessingSecurityScopedResource()
            }
            if finalURL.path != source.path {
                updated[index].sourceURL = finalURL
                if let j = lastInputURLs.firstIndex(where: { $0.path == source.path }) {
                    lastInputURLs[j] = finalURL
                }
            }
            updated[index].proposedName = targetName
            updated[index].originalName = targetName
            updated[index].statusMessage = renamedStatus
            return true
        } catch {
            if granted {
                source.stopAccessingSecurityScopedResource()
            }
            updated[index].statusMessage = renameErrorMessage(error.localizedDescription)
            return false
        }
    }
}
