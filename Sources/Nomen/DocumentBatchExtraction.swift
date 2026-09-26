import Foundation
import NomenCore

/// Parallelisierte Textextraktion für einen Analyse-Batch (Cap + Fortschritts-Callbacks).
/// UI-/Inferenz-Orchestrierung bleibt im ViewModel.
@MainActor
enum DocumentBatchExtraction {
    struct Pending: Sendable {
        let mergeIdx: Int
        let url: URL
        let originalName: String
        let ext: String
        let snap: DocumentAIProcessor.ExtractionSnapshot
        let modificationDate: Date
    }

    enum Outcome: Sendable {
        case success(Pending)
        case failure(mergeIdx: Int, url: URL, originalName: String, message: String)

        var mergeIndex: Int {
            switch self {
            case .success(let item): return item.mergeIdx
            case .failure(let mergeIdx, _, _, _): return mergeIdx
            }
        }
    }

    /// Extrahiert alle ausstehenden Dateien mit begrenzter Parallelität.
    static func extractPendingFiles(
        merged: [URL],
        pendingIndices: [Int],
        shouldContinue: () -> Bool,
        onProgress: (_ finished: Int, _ total: Int) -> Void
    ) async -> [Outcome] {
        var outcomes: [Outcome] = []
        outcomes.reserveCapacity(pendingIndices.count)

        await withTaskGroup(of: Outcome.self) { group in
            var next = 0
            var inFlight = 0
            let parallelCap = 6

            func enqueue() {
                while inFlight < parallelCap, next < pendingIndices.count {
                    let mergeIdx = pendingIndices[next]
                    next += 1
                    inFlight += 1
                    let url = merged[mergeIdx]
                    group.addTask {
                        await extractOne(url: url, mergeIdx: mergeIdx)
                    }
                }
            }

            enqueue()
            var finished = 0
            let total = max(pendingIndices.count, 1)
            for await outcome in group {
                inFlight -= 1
                finished += 1
                outcomes.append(outcome)
                if shouldContinue() {
                    onProgress(finished, total)
                }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                enqueue()
            }
        }

        return outcomes.sorted { $0.mergeIndex < $1.mergeIndex }
    }

    nonisolated private static func extractOne(url: URL, mergeIdx: Int) async -> Outcome {
        let originalName = url.lastPathComponent
        let ext = url.pathExtension
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let snap = try await DocumentAIProcessor.extractForRenaming(
                url: url,
                extLowercased: ext.lowercased()
            )
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let mod = attrs[.modificationDate] as? Date ?? Date()
            return .success(
                Pending(
                    mergeIdx: mergeIdx,
                    url: url,
                    originalName: originalName,
                    ext: ext,
                    snap: snap,
                    modificationDate: mod
                )
            )
        } catch {
            return .failure(
                mergeIdx: mergeIdx,
                url: url,
                originalName: originalName,
                message: error.localizedDescription
            )
        }
    }
}
