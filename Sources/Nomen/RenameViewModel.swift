import AppKit
import Foundation
import NomenCore

private let maxParallelExtractions = 6
private let liveProgressInterval: Duration = .milliseconds(90)

@MainActor
final class RenameProgressState: ObservableObject {
    @Published var label: String = ""
    @Published var value: Double = 0
}

@MainActor
final class RenameViewModel: ObservableObject {
    @Published var schema: DateNameSchema = .yearMonthTitle
    @Published private(set) var rows: [RenamePreviewRow] = [] {
        didSet { reindexRows() }
    }
    @Published private(set) var phase: RenameAnalysisPhase = .idle
    @Published var errorMessage: String?
    @Published private(set) var renameFeedbackPhase: RenameFeedbackPhase = .idle
    let progress = RenameProgressState()

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
    private var rowByID: [UUID: RenamePreviewRow] = [:]
    private var lastProgressPublish: ContinuousClock.Instant?

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

    func row(id: UUID) -> RenamePreviewRow? {
        rowByID[id]
    }

    private func reindexRows() {
        var map: [UUID: RenamePreviewRow] = [:]
        map.reserveCapacity(rows.count)
        for r in rows {
            map[r.id] = r
        }
        rowByID = map
    }

    private func setProgress(value: Double, label: String, force: Bool = false) {
        let labelChanged = progress.label != label
        let valueChanged = abs(progress.value - value) >= 0.006
        guard force || labelChanged || valueChanged else { return }
        if !force, let last = lastProgressPublish, ContinuousClock.now - last < liveProgressInterval {
            return
        }
        lastProgressPublish = .now
        if labelChanged {
            progress.label = label
        }
        if valueChanged || force {
            progress.value = value
        }
    }

    private static func interRenameDelay(total: Int) -> Duration? {
        switch total {
        case 1...6: return .milliseconds(50)
        case 7...25: return .milliseconds(16)
        default: return nil
        }
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
        lastProgressPublish = nil
        progress.label = ""
        progress.value = 0
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
            progress.label = ""
        } else {
            progress.label = t.progressDone
        }
    }

    func removeRows(ids: Set<UUID>) {
        guard !isRenaming else { return }
        rows.removeAll { ids.contains($0.id) }
        lastInputURLs = rows.map(\.sourceURL)
        if rows.isEmpty {
            phase = .idle
            progress.label = ""
            progress.value = 0
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
        if total <= 8 {
            try? await Task.sleep(for: .milliseconds(60))
        }

        var updated = rows
        var successCount = 0
        var failureCount = 0
        let stepDelay = Self.interRenameDelay(total: total)

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
            if let stepDelay {
                try? await Task.sleep(for: stepDelay)
            }
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
            setProgress(value: existing.isEmpty ? 0 : 1, label: existing.isEmpty ? "" : t.progressDone, force: true)
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
        setProgress(value: 0, label: t.progressExtract, force: true)

        let documentCount = pendingIndices.count
        let hasPDF = pendingIndices.contains {
            merged[$0].pathExtension.lowercased() == SupportedDocumentFormat.pdf.rawValue
        }
        if hasPDF {
            phase = .ocr
            setProgress(value: progress.value, label: t.progressOCR, force: true)
        }

        let extracts = await extractPendingFiles(
            merged: merged,
            pendingIndices: pendingIndices,
            run: run
        )
        if Task.isCancelled || run != analysisRun {
            applyPartialAnalysisIfCurrentRun(run: run, built: completedRows(builtRows))
            return
        }

        for outcome in extracts {
            if case .failure(let mergeIdx, let url, let originalName, let message) = outcome {
                builtRows[mergeIdx] = DocumentFileAnalyzer.makeFailedRow(
                    id: builtRows[mergeIdx].id,
                    url: url,
                    originalName: originalName,
                    message: message
                )
            }
        }
        rows = builtRows

        let successes = extracts.compactMap { outcome -> ExtractedPending? in
            if case .success(let item) = outcome { return item }
            return nil
        }
        .sorted { $0.mergeIdx < $1.mergeIdx }

        phase = .understanding
        let inferTotal = max(successes.count, 1)
        for (progressIdx, item) in successes.enumerated() {
            if Task.isCancelled {
                applyPartialAnalysisIfCurrentRun(run: run, built: completedRows(builtRows))
                return
            }

            setProgress(
                value: 0.45 + (Double(progressIdx) / Double(inferTotal)) * 0.55,
                label: analysisBatchLabel(
                    documentIndex: progressIdx + 1,
                    documentCount: documentCount,
                    phase: t.progressNL(inferenceBackend: namingInferenceBackend)
                ),
                force: true
            )

            let languageMode = outputLanguageMode
            let backend = namingInferenceBackend
            let localeId = uiLanguage == .german ? "de_DE" : "en_US"
            let pkg = await OnDeviceDocumentAnalyzer.analyzePackage(
                sampleText: item.snap.combinedText,
                fileModificationDate: item.modificationDate,
                fallbackFilenameStem: item.url.deletingPathExtension().lastPathComponent,
                localeIdentifier: localeId,
                outputLanguageMode: languageMode,
                inferenceBackend: backend
            )
            builtRows[item.mergeIdx] = DocumentFileAnalyzer.makeCompletedRow(
                id: builtRows[item.mergeIdx].id,
                url: item.url,
                originalName: item.originalName,
                extension: item.ext,
                schema: schemaSnapshot,
                snap: item.snap,
                fileModificationDate: item.modificationDate,
                package: pkg,
                strings: t,
                includePipelineDebug: AppPreferences.showPipelineDebug
            )
            rows = builtRows
            setProgress(
                value: 0.45 + (Double(progressIdx + 1) / Double(inferTotal)) * 0.55,
                label: progress.label,
                force: true
            )
        }

        guard run == analysisRun else {
            return
        }
        rows = builtRows
        phase = .ready
        setProgress(value: 1, label: t.progressDone, force: true)
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

    /// Fertige Zeilen in Listenreihenfolge (Platzhalter entfallen — auch bei außer der Reihe abgeschlossener Parallel-Extraktion).
    private func completedRows(_ builtRows: [RenamePreviewRow]) -> [RenamePreviewRow] {
        builtRows.filter { !$0.isAnalysisPlaceholder }
    }

    private func applyPartialAnalysisIfCurrentRun(run: Int, built: [RenamePreviewRow]) {
        guard run == analysisRun else {
            return
        }
        rows = built
        phase = .ready
        setProgress(
            value: built.isEmpty ? 0 : 1,
            label: built.isEmpty ? "" : t.analysisStopped,
            force: true
        )
        lastInputURLs = built.map(\.sourceURL)
        analysisTask = nil
    }

    private func analysisBatchLabel(documentIndex: Int, documentCount: Int, phase: String) -> String {
        guard documentCount > 1 else { return phase }
        return "\(t.progressDocumentsBatch(current: documentIndex, total: documentCount)) — \(phase)"
    }

    private func extractPendingFiles(
        merged: [URL],
        pendingIndices: [Int],
        run: Int
    ) async -> [ExtractOutcome] {
        var outcomes: [ExtractOutcome] = []
        outcomes.reserveCapacity(pendingIndices.count)

        await withTaskGroup(of: ExtractOutcome.self) { group in
            var next = 0
            var inFlight = 0

            func enqueue() {
                while inFlight < maxParallelExtractions, next < pendingIndices.count {
                    let mergeIdx = pendingIndices[next]
                    next += 1
                    inFlight += 1
                    let url = merged[mergeIdx]
                    group.addTask {
                        await Self.extractOne(url: url, mergeIdx: mergeIdx)
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
                if run == analysisRun {
                    setProgress(
                        value: (Double(finished) / Double(total)) * 0.45,
                        label: analysisBatchLabel(
                            documentIndex: finished,
                            documentCount: pendingIndices.count,
                            phase: t.progressExtract
                        ),
                        force: finished == pendingIndices.count
                    )
                }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                enqueue()
            }
        }

        return outcomes.sorted { lhs, rhs in
            extractMergeIndex(lhs) < extractMergeIndex(rhs)
        }
    }

    private func extractMergeIndex(_ outcome: ExtractOutcome) -> Int {
        switch outcome {
        case .success(let item): return item.mergeIdx
        case .failure(let mergeIdx, _, _, _): return mergeIdx
        }
    }

    nonisolated private static func extractOne(url: URL, mergeIdx: Int) async -> ExtractOutcome {
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
                ExtractedPending(
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

private struct ExtractedPending: Sendable {
    let mergeIdx: Int
    let url: URL
    let originalName: String
    let ext: String
    let snap: DocumentAIProcessor.ExtractionSnapshot
    let modificationDate: Date
}

private enum ExtractOutcome: Sendable {
    case success(ExtractedPending)
    case failure(mergeIdx: Int, url: URL, originalName: String, message: String)
}
