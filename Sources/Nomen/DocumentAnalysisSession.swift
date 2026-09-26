import Foundation
import NomenCore

/// Orchestriert Extraktion + Inferenz für einen Analyse-Batch.
/// ViewModel bleibt für Published-State und Task-Lifecycle zuständig.
@MainActor
enum DocumentAnalysisSession {
    /// Apple Foundation Models: begrenzte Parallelität. GGUF: seriell (Shared Actor).
    static func inferenceConcurrency(for backend: NamingInferenceBackend) -> Int {
        switch backend {
        case .appleFoundation: return 2
        case .llamaQwenGGUF: return 1
        }
    }

    struct Config {
        let schema: DateNameSchema
        let outputLanguageMode: OutputLanguageMode
        let namingInferenceBackend: NamingInferenceBackend
        let uiLanguage: AppLanguage
        let strings: L10n
        let includePipelineDebug: Bool
    }

    enum Event {
        case phase(RenameAnalysisPhase)
        /// Volle Listenersetzung (Platzhalter, Partial-Stop, finale Sync).
        case rows([RenamePreviewRow])
        /// Einzelne Zeile (Infer-/Fehler-Updates ohne volle Array-Kopie an die UI).
        case row(at: Int, RenamePreviewRow)
        case progress(value: Double, label: String, force: Bool)
        case lastInputURLs([URL])
        case finished
    }

    static func run(
        merged: [URL],
        isCurrentRun: @escaping () -> Bool,
        initialRows: [RenamePreviewRow],
        config: Config,
        emit: (Event) -> Void
    ) async {
        let t = config.strings
        var rowByPath: [String: RenamePreviewRow] = [:]
        rowByPath.reserveCapacity(initialRows.count)
        for r in initialRows {
            rowByPath[r.sourceURL.path] = r
        }

        let pendingIndices: [Int] = merged.enumerated().compactMap {
            rowByPath[$0.element.path] == nil ? $0.offset : nil
        }

        if pendingIndices.isEmpty {
            guard isCurrentRun() else { return }
            var existing = merged.compactMap { rowByPath[$0.path] }
            if existing.count < initialRows.count {
                existing = initialRows
            }
            emit(.lastInputURLs(existing.map(\.sourceURL)))
            emit(.rows(existing))
            emit(.phase(.ready))
            emit(.progress(
                value: existing.isEmpty ? 0 : 1,
                label: existing.isEmpty ? "" : t.progressDone,
                force: true
            ))
            emit(.finished)
            return
        }

        var builtRows: [RenamePreviewRow] = merged.map { url in
            if let existing = rowByPath[url.path] {
                return existing
            }
            return makeAnalysisPlaceholderRow(url: url, strings: t)
        }
        emit(.rows(builtRows))
        emit(.phase(.extracting))
        emit(.progress(value: 0, label: t.progressExtract, force: true))

        let documentCount = pendingIndices.count
        let hasPDF = pendingIndices.contains {
            merged[$0].pathExtension.lowercased() == SupportedDocumentFormat.pdf.rawValue
        }
        if hasPDF {
            emit(.phase(.ocr))
            emit(.progress(value: 0, label: t.progressOCR, force: true))
        }

        let extracts = await DocumentBatchExtraction.extractPendingFiles(
            merged: merged,
            pendingIndices: pendingIndices,
            shouldContinue: isCurrentRun,
            onProgress: { finished, total in
                emit(.progress(
                    value: (Double(finished) / Double(total)) * 0.45,
                    label: analysisBatchLabel(
                        documentIndex: finished,
                        documentCount: pendingIndices.count,
                        phase: t.progressExtract,
                        strings: t
                    ),
                    force: finished == pendingIndices.count
                ))
            }
        )
        if Task.isCancelled || !isCurrentRun() {
            applyPartial(builtRows: builtRows, isCurrentRun: isCurrentRun, strings: t, emit: emit)
            return
        }

        for outcome in extracts {
            if case .failure(let mergeIdx, let url, let originalName, let message) = outcome {
                let failed = DocumentFileAnalyzer.makeFailedRow(
                    id: builtRows[mergeIdx].id,
                    url: url,
                    originalName: originalName,
                    message: message
                )
                builtRows[mergeIdx] = failed
                emit(.row(at: mergeIdx, failed))
            }
        }

        let successes = extracts.compactMap { outcome -> DocumentBatchExtraction.Pending? in
            if case .success(let item) = outcome { return item }
            return nil
        }
        .sorted { $0.mergeIdx < $1.mergeIdx }

        emit(.phase(.understanding))
        let cancelled = await runInference(
            successes: successes,
            documentCount: documentCount,
            builtRows: &builtRows,
            config: config,
            isCurrentRun: isCurrentRun,
            emit: emit
        )
        if cancelled {
            applyPartial(builtRows: builtRows, isCurrentRun: isCurrentRun, strings: t, emit: emit)
            return
        }

        guard isCurrentRun() else { return }
        emit(.rows(builtRows))
        emit(.phase(.ready))
        emit(.progress(value: 1, label: t.progressDone, force: true))
        emit(.lastInputURLs(merged))
        emit(.finished)
    }

    /// Rückgabe `true`, wenn abgebrochen (Partial anwenden).
    private static func runInference(
        successes: [DocumentBatchExtraction.Pending],
        documentCount: Int,
        builtRows: inout [RenamePreviewRow],
        config: Config,
        isCurrentRun: @escaping () -> Bool,
        emit: (Event) -> Void
    ) async -> Bool {
        let t = config.strings
        let inferTotal = max(successes.count, 1)
        let concurrency = inferenceConcurrency(for: config.namingInferenceBackend)
        let localeId = config.uiLanguage == .german ? "de_DE" : "en_US"
        let schema = config.schema
        let languageMode = config.outputLanguageMode
        let backend = config.namingInferenceBackend
        let includeDebug = config.includePipelineDebug

        if successes.isEmpty {
            return false
        }

        // Seriell: gleiche Fortschritts-Semantik wie zuvor (Index vor Abschluss).
        if concurrency <= 1 {
            for (progressIdx, item) in successes.enumerated() {
                if Task.isCancelled { return true }

                let inferLabel = analysisBatchLabel(
                    documentIndex: progressIdx + 1,
                    documentCount: documentCount,
                    phase: t.progressNL(inferenceBackend: backend),
                    strings: t
                )
                emit(.progress(
                    value: 0.45 + (Double(progressIdx) / Double(inferTotal)) * 0.55,
                    label: inferLabel,
                    force: true
                ))

                let rowID = builtRows[item.mergeIdx].id
                let completed = await inferOne(
                    item: item,
                    rowID: rowID,
                    schema: schema,
                    localeId: localeId,
                    languageMode: languageMode,
                    backend: backend,
                    strings: t,
                    includePipelineDebug: includeDebug
                )
                builtRows[item.mergeIdx] = completed
                emit(.row(at: item.mergeIdx, completed))
                emit(.progress(
                    value: 0.45 + (Double(progressIdx + 1) / Double(inferTotal)) * 0.55,
                    label: inferLabel,
                    force: true
                ))
            }
            return false
        }

        // Parallel (Apple): Fortschritt nach abgeschlossenen Inferences.
        var didCancel = false
        await withTaskGroup(of: InferOutcome.self) { group in
            var next = 0
            var inFlight = 0

            func enqueue() {
                while inFlight < concurrency, next < successes.count {
                    let item = successes[next]
                    next += 1
                    inFlight += 1
                    let rowID = builtRows[item.mergeIdx].id
                    group.addTask {
                        let row = await inferOne(
                            item: item,
                            rowID: rowID,
                            schema: schema,
                            localeId: localeId,
                            languageMode: languageMode,
                            backend: backend,
                            strings: t,
                            includePipelineDebug: includeDebug
                        )
                        return InferOutcome(mergeIdx: item.mergeIdx, row: row)
                    }
                }
            }

            enqueue()
            var finished = 0
            for await outcome in group {
                inFlight -= 1
                finished += 1
                builtRows[outcome.mergeIdx] = outcome.row
                emit(.row(at: outcome.mergeIdx, outcome.row))

                let inferLabel = analysisBatchLabel(
                    documentIndex: finished,
                    documentCount: documentCount,
                    phase: t.progressNL(inferenceBackend: backend),
                    strings: t
                )
                emit(.progress(
                    value: 0.45 + (Double(finished) / Double(inferTotal)) * 0.55,
                    label: inferLabel,
                    force: true
                ))

                if Task.isCancelled || !isCurrentRun() {
                    didCancel = true
                    group.cancelAll()
                    break
                }
                enqueue()
            }
        }
        return didCancel
    }

    private nonisolated static func inferOne(
        item: DocumentBatchExtraction.Pending,
        rowID: UUID,
        schema: DateNameSchema,
        localeId: String,
        languageMode: OutputLanguageMode,
        backend: NamingInferenceBackend,
        strings: L10n,
        includePipelineDebug: Bool
    ) async -> RenamePreviewRow {
        let pkg = await OnDeviceDocumentAnalyzer.analyzePackage(
            sampleText: item.snap.combinedText,
            fileModificationDate: item.modificationDate,
            fallbackFilenameStem: item.url.deletingPathExtension().lastPathComponent,
            localeIdentifier: localeId,
            outputLanguageMode: languageMode,
            inferenceBackend: backend
        )
        return DocumentFileAnalyzer.makeCompletedRow(
            id: rowID,
            url: item.url,
            originalName: item.originalName,
            extension: item.ext,
            schema: schema,
            snap: item.snap,
            fileModificationDate: item.modificationDate,
            package: pkg,
            strings: strings,
            includePipelineDebug: includePipelineDebug
        )
    }

    private static func makeAnalysisPlaceholderRow(url: URL, strings: L10n) -> RenamePreviewRow {
        let name = url.lastPathComponent
        return RenamePreviewRow(
            id: UUID(),
            sourceURL: url,
            originalName: name,
            proposedName: name,
            statusMessage: strings.rowPendingAnalysis,
            usedFallbackDate: false,
            namingBasis: nil,
            pipelineDebug: nil,
            isAnalysisPlaceholder: true
        )
    }

    private static func applyPartial(
        builtRows: [RenamePreviewRow],
        isCurrentRun: () -> Bool,
        strings: L10n,
        emit: (Event) -> Void
    ) {
        guard isCurrentRun() else { return }
        let built = builtRows.filter { !$0.isAnalysisPlaceholder }
        emit(.rows(built))
        emit(.phase(.ready))
        emit(.progress(
            value: built.isEmpty ? 0 : 1,
            label: built.isEmpty ? "" : strings.analysisStopped,
            force: true
        ))
        emit(.lastInputURLs(built.map(\.sourceURL)))
        emit(.finished)
    }

    private static func analysisBatchLabel(
        documentIndex: Int,
        documentCount: Int,
        phase: String,
        strings: L10n
    ) -> String {
        guard documentCount > 1 else { return phase }
        return "\(strings.progressDocumentsBatch(current: documentIndex, total: documentCount)) — \(phase)"
    }
}

private struct InferOutcome: Sendable {
    let mergeIdx: Int
    let row: RenamePreviewRow
}
