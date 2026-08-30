import AppKit
import Foundation

@MainActor
final class RenameViewModel: ObservableObject {
    @Published var schema: DateNameSchema = .yearMonthTitle
    @Published private(set) var rows: [RenamePreviewRow] = []
    @Published private(set) var phase: RenameAnalysisPhase = .idle
    @Published private(set) var progressLabel: String = ""
    @Published private(set) var progressValue: Double = 0
    @Published var errorMessage: String?
    @Published private(set) var renameFeedbackPhase: RenameFeedbackPhase = .idle

    /// Synced from the UI (AppStorage) so progress strings match the chosen language.
    var uiLanguage: AppLanguage = .english

    /// Synced from the UI (AppStorage) so the model receives the right language instruction.
    var outputLanguageMode: OutputLanguageMode = .followDocument

    /// Apple Foundation Models vs. lokales Qwen2.5-7B-GGUF (llama.cpp).
    var namingInferenceBackend: NamingInferenceBackend = .appleFoundation

    private var lastInputURLs: [URL] = []

    /// Bricht alte Analysen ab, wenn ein neuer Batch startet (ohne Teilergebnisse zu vermischen).
    private var analysisRun: Int = 0
    private var analysisTask: Task<Void, Never>?
    private var renameTask: Task<Void, Never>?

    private var t: L10n { L10n(uiLanguage) }

    var isBusy: Bool {
        phase != .idle && phase != .ready
    }

    var isRenaming: Bool {
        renameFeedbackPhase != .idle
    }

    var canRename: Bool {
        !rows.isEmpty && !isBusy && !isRenaming
    }

    func addFiles(urls: [URL]) {
        guard !isRenaming else { return }
        errorMessage = nil
        let filtered = urls.filter { SupportedDocumentFormat.isSupported(url: $0) }
        guard !filtered.isEmpty else {
            errorMessage = t.noSupportedFiles
            return
        }
        var seen = Set<String>()
        var merged: [URL] = []
        for u in lastInputURLs + filtered where seen.insert(u.path).inserted {
            merged.append(u)
        }
        lastInputURLs = merged
        analysisRun += 1
        let run = analysisRun
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.analyze(urls: merged, run: run)
        }
    }

    func stopAnalysis() {
        analysisTask?.cancel()
    }

    func clear() {
        renameTask?.cancel()
        renameTask = nil
        renameFeedbackPhase = .idle
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun += 1
        rows = []
        lastInputURLs = []
        phase = .idle
        progressLabel = ""
        progressValue = 0
        errorMessage = nil
    }

    func refreshAfterSchemaChange() {
        guard !isBusy, phase == .ready, !rows.isEmpty else { return }
        reapplySchemaOnly()
    }

    /// Recomputes preview filenames from cached `namingBasis` (no PDF/OCR re-run).
    private func reapplySchemaOnly() {
        let schemaSnapshot = schema
        var updated = rows
        for i in updated.indices {
            guard let basis = updated[i].namingBasis,
                  let date = basis.documentDate else { continue }

            let ext = updated[i].sourceURL.pathExtension
            let proposedBase = FilenameFormatting.formatFilename(
                schema: schemaSnapshot,
                title: basis.title,
                date: date,
                originalExtension: ext
            )
            let directory = updated[i].sourceURL.deletingLastPathComponent()
            let unique = FileRenameOperations.uniquifyFilename(
                desiredName: proposedBase,
                directory: directory,
                ignoreIfSameAs: updated[i].sourceURL
            )
            updated[i].proposedName = unique
            updated[i].statusMessage = basis.usedContentDate ? t.dateFromContent : t.dateFromFile
            updated[i].usedFallbackDate = !basis.usedContentDate
        }
        rows = updated
    }

    func syncFooterAfterLanguageChange() {
        guard phase == .ready else { return }
        if rows.isEmpty {
            progressLabel = ""
        } else {
            progressLabel = t.progressDone
        }
    }

    func removeRows(ids: Set<UUID>) {
        guard !isRenaming else { return }
        rows.removeAll { ids.contains($0.id) }
        lastInputURLs = rows.map(\.sourceURL)
        if rows.isEmpty {
            phase = .idle
            progressLabel = ""
            progressValue = 0
        }
    }

    func renameRows(ids: Set<UUID>) {
        guard !isBusy, !isRenaming else { return }
        let indices = rows.enumerated().compactMap { pair -> Int? in
            guard ids.contains(pair.element.id), !pair.element.isAnalysisPlaceholder else { return nil }
            return pair.offset
        }
        guard !indices.isEmpty else { return }
        startRenameSession(indices: indices, renamedEntireList: indices.count == rows.count)
    }

    func renameAll() {
        guard canRename else { return }
        startRenameSession(indices: Array(rows.indices), renamedEntireList: true)
    }

    private var clearListAfterSuccessfulRename: Bool {
        AppPreferences.clearListAfterSuccessfulRename
    }

    private func startRenameSession(indices: [Int], renamedEntireList: Bool) {
        errorMessage = nil
        renameTask?.cancel()
        renameTask = Task { [weak self] in
            await self?.runRenameSession(indices: indices, renamedEntireList: renamedEntireList)
        }
    }

    private func runRenameSession(indices: [Int], renamedEntireList: Bool) async {
        defer { renameTask = nil }

        let total = indices.count
        guard total > 0 else { return }

        renameFeedbackPhase = .working(done: 0, total: total)
        try? await Task.sleep(for: .milliseconds(60))

        var updated = rows
        var successCount = 0
        var failureCount = 0

        for (step, idx) in indices.enumerated() {
            if Task.isCancelled {
                rows = updated
                renameFeedbackPhase = .idle
                return
            }
            guard updated.indices.contains(idx) else { continue }

            if applyRename(at: idx, updated: &updated) {
                successCount += 1
            } else {
                failureCount += 1
            }
            rows = updated
            renameFeedbackPhase = .working(done: step + 1, total: total)
            try? await Task.sleep(for: .milliseconds(55))
        }

        lastInputURLs = rows.map(\.sourceURL)

        let shouldClear = clearListAfterSuccessfulRename

        if successCount == 0, failureCount > 0 {
            renameFeedbackPhase = .outcome(
                kind: .allFailed,
                renamedCount: 0,
                renamedEntireList: renamedEntireList
            )
            try? await Task.sleep(for: .milliseconds(700))
            renameFeedbackPhase = .idle
            return
        }

        if successCount > 0, failureCount == 0 {
            renameFeedbackPhase = .outcome(
                kind: .success,
                renamedCount: successCount,
                renamedEntireList: renamedEntireList
            )
            try? await Task.sleep(for: .milliseconds(880))
            if shouldClear, renamedEntireList {
                clear()
            } else {
                renameFeedbackPhase = .idle
            }
            return
        }

        renameFeedbackPhase = .outcome(
            kind: .partialFailure,
            renamedCount: successCount,
            renamedEntireList: renamedEntireList
        )
        try? await Task.sleep(for: .milliseconds(900))
        renameFeedbackPhase = .idle
    }

    /// Führt die Umbenennung für eine Zeile aus. Rückgabe **true**, wenn kein Fehler aufgetreten ist.
    private func applyRename(at index: Int, updated: inout [RenamePreviewRow]) -> Bool {
        let source = updated[index].sourceURL
        do {
            let (finalURL, targetName) = try SecurityScopedResource.accessing(source) {
                try FileRenameOperations.renameIfNeeded(
                    source: source,
                    desiredName: updated[index].proposedName
                )
            }
            if finalURL.path != source.path {
                updated[index].sourceURL = finalURL
                if let j = lastInputURLs.firstIndex(where: { $0.path == source.path }) {
                    lastInputURLs[j] = finalURL
                }
            }
            updated[index].proposedName = targetName
            updated[index].originalName = targetName
            updated[index].statusMessage = t.renamed
            return true
        } catch {
            updated[index].statusMessage = t.renameError(error.localizedDescription)
            return false
        }
    }

    private func analyze(urls merged: [URL], run: Int) async {
        let schemaSnapshot = schema

        var rowByPath: [String: RenamePreviewRow] = [:]
        rowByPath.reserveCapacity(rows.count)
        for r in rows {
            rowByPath[r.sourceURL.path] = r
        }

        let pendingIndices: [Int] = merged.enumerated().compactMap { rowByPath[$0.element.path] == nil ? $0.offset : nil }

        if pendingIndices.isEmpty {
            guard run == analysisRun else { return }
            var existing = merged.compactMap { rowByPath[$0.path] }
            if existing.count < rows.count {
                existing = rows
            }
            lastInputURLs = existing.map(\.sourceURL)
            rows = existing
            phase = .ready
            progressValue = existing.isEmpty ? 0 : 1
            progressLabel = existing.isEmpty ? "" : t.progressDone
            analysisTask = nil
            return
        }

        var builtRows: [RenamePreviewRow] = merged.map { url in
            if let existing = rowByPath[url.path] {
                return existing
            }
            return makeAnalysisPlaceholderRow(url: url)
        }
        rows = builtRows

        phase = .extracting
        progressValue = 0
        progressLabel = t.progressExtract

        let total = Double(pendingIndices.count)
        let documentCount = pendingIndices.count

        for (progressIdx, mergeIdx) in pendingIndices.enumerated() {
            if Task.isCancelled {
                applyPartialAnalysisIfCurrentRun(
                    run: run,
                    built: contiguousCompletedRows(builtRows)
                )
                return
            }

            let url = merged[mergeIdx]
            let fileBase = Double(progressIdx) / max(total, 1)
            let fileSlice = 1.0 / max(total, 1)
            progressValue = fileBase
            let docIndex = progressIdx + 1

            let originalName = url.lastPathComponent
            let ext = url.pathExtension

            do {
                let granted = url.startAccessingSecurityScopedResource()
                defer {
                    if granted { url.stopAccessingSecurityScopedResource() }
                }
                let row = try await analyzeOneFile(
                    url: url,
                    originalName: originalName,
                    ext: ext,
                    schemaSnapshot: schemaSnapshot,
                    fileBase: fileBase,
                    fileSlice: fileSlice,
                    documentIndex: docIndex,
                    documentCount: documentCount
                )
                builtRows[mergeIdx] = row
                progressValue = fileBase + fileSlice
            } catch {
                builtRows[mergeIdx] = DocumentFileAnalyzer.makeFailedRow(
                    url: url,
                    originalName: originalName,
                    message: error.localizedDescription
                )
                progressValue = fileBase + fileSlice
            }

            rows = builtRows

            if Task.isCancelled {
                applyPartialAnalysisIfCurrentRun(
                    run: run,
                    built: contiguousCompletedRows(builtRows)
                )
                return
            }
        }

        guard run == analysisRun else {
            return
        }
        rows = builtRows
        phase = .ready
        progressValue = 1
        progressLabel = t.progressDone
        lastInputURLs = merged
        analysisTask = nil
    }

    private func makeAnalysisPlaceholderRow(url: URL) -> RenamePreviewRow {
        let name = url.lastPathComponent
        return RenamePreviewRow(
            id: UUID(),
            sourceURL: url,
            originalName: name,
            proposedName: name,
            statusMessage: t.rowPendingAnalysis,
            usedFallbackDate: false,
            namingBasis: nil,
            pipelineDebug: nil,
            isAnalysisPlaceholder: true
        )
    }

    /// Abgeschlossene Zeilen bis zur ersten noch laufenden Platzhalter-Zeile (für Abbruch und konsistente `lastInputURLs`).
    private func contiguousCompletedRows(_ builtRows: [RenamePreviewRow]) -> [RenamePreviewRow] {
        var out: [RenamePreviewRow] = []
        for r in builtRows {
            if r.isAnalysisPlaceholder {
                break
            }
            out.append(r)
        }
        return out
    }

    private func applyPartialAnalysisIfCurrentRun(run: Int, built: [RenamePreviewRow]) {
        guard run == analysisRun else {
            return
        }
        rows = built
        phase = .ready
        progressValue = built.isEmpty ? 0 : 1
        progressLabel = built.isEmpty ? "" : t.analysisStopped
        lastInputURLs = built.map(\.sourceURL)
        analysisTask = nil
    }

    private func analysisBatchLabel(documentIndex: Int, documentCount: Int, phase: String) -> String {
        guard documentCount > 1 else { return phase }
        return "\(t.progressDocumentsBatch(current: documentIndex, total: documentCount)) — \(phase)"
    }

    private func analyzeOneFile(
        url: URL,
        originalName: String,
        ext: String,
        schemaSnapshot: DateNameSchema,
        fileBase: Double,
        fileSlice: Double,
        documentIndex: Int,
        documentCount: Int
    ) async throws -> RenamePreviewRow {
        phase = .extracting
        progressLabel = analysisBatchLabel(
            documentIndex: documentIndex,
            documentCount: documentCount,
            phase: t.progressExtract
        )

        if ext.lowercased() == SupportedDocumentFormat.pdf.rawValue {
            phase = .ocr
            progressLabel = analysisBatchLabel(
                documentIndex: documentIndex,
                documentCount: documentCount,
                phase: t.progressOCR
            )
            progressValue = fileBase + fileSlice * 0.02
        }
        let snap = try await DocumentAIProcessor.extractForRenaming(
            url: url,
            extLowercased: ext.lowercased()
        )

        if ext.lowercased() == SupportedDocumentFormat.pdf.rawValue {
            progressValue = fileBase + fileSlice * 0.46
        } else {
            progressValue = fileBase + fileSlice * 0.35
        }

        phase = .understanding
        progressLabel = analysisBatchLabel(
            documentIndex: documentIndex,
            documentCount: documentCount,
            phase: t.progressNL(inferenceBackend: namingInferenceBackend)
        )
        progressValue = fileBase + fileSlice * 0.52

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mod = attrs[.modificationDate] as? Date ?? Date()
        let stem = url.deletingPathExtension().lastPathComponent
        let localeId = uiLanguage == .german ? "de_DE" : "en_US"

        let pkg = await OnDeviceDocumentAnalyzer.analyzePackage(
            sampleText: snap.combinedText,
            fileModificationDate: mod,
            fallbackFilenameStem: stem,
            localeIdentifier: localeId,
            outputLanguageMode: outputLanguageMode,
            inferenceBackend: namingInferenceBackend
        )

        return DocumentFileAnalyzer.makeCompletedRow(
            url: url,
            originalName: originalName,
            extension: ext,
            schema: schemaSnapshot,
            snap: snap,
            fileModificationDate: mod,
            package: pkg,
            strings: t,
            includePipelineDebug: AppPreferences.showPipelineDebug
        )
    }
}
