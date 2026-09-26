import AppKit
import Foundation
import NomenCore

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

    /// Inkrementelles Update ohne volle Array-Zuweisung an SwiftUI (objectWillChange manuell).
    private func updateRow(at index: Int, _ row: RenamePreviewRow) {
        guard rows.indices.contains(index) else { return }
        objectWillChange.send()
        rows[index] = row
        rowByID[row.id] = row
    }

    private func replaceRows(_ newRows: [RenamePreviewRow]) {
        rows = newRows
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

    private func startRenameSession(indices: [Int], renamedEntireList: Bool) {
        errorMessage = nil
        renameTask?.cancel()
        renameTask = Task { [weak self] in
            await self?.runRenameSession(indices: indices, renamedEntireList: renamedEntireList)
        }
    }

    private func runRenameSession(indices: [Int], renamedEntireList: Bool) async {
        defer { renameTask = nil }

        let outcome = await DocumentRenameSession.run(
            rows: rows,
            lastInputURLs: lastInputURLs,
            indices: indices,
            renamedEntireList: renamedEntireList,
            clearListAfterSuccessfulRename: AppPreferences.clearListAfterSuccessfulRename,
            renamedStatus: t.renamed,
            renameErrorMessage: { t.renameError($0) },
            emit: { [weak self] event in
                guard let self else { return }
                switch event {
                case .feedback(let phase):
                    self.renameFeedbackPhase = phase
                case .rows(let updated):
                    self.replaceRows(updated)
                case .row(at: let index, let row):
                    self.updateRow(at: index, row)
                }
            }
        )

        guard let outcome else { return }
        lastInputURLs = outcome.lastInputURLs
        if outcome.shouldClearList {
            clear()
        }
    }

    private func analyze(urls merged: [URL], run: Int) async {
        await DocumentAnalysisSession.run(
            merged: merged,
            isCurrentRun: { [weak self] in
                guard let self else { return false }
                return run == self.analysisRun
            },
            initialRows: rows,
            config: DocumentAnalysisSession.Config(
                schema: schema,
                outputLanguageMode: outputLanguageMode,
                namingInferenceBackend: namingInferenceBackend,
                uiLanguage: uiLanguage,
                strings: t,
                includePipelineDebug: AppPreferences.showPipelineDebug
            ),
            emit: { [weak self] event in
                guard let self else { return }
                switch event {
                case .phase(let phase):
                    self.phase = phase
                case .rows(let rows):
                    self.replaceRows(rows)
                case .row(at: let index, let row):
                    self.updateRow(at: index, row)
                case .progress(let value, let label, let force):
                    self.setProgress(value: value, label: label, force: force)
                case .lastInputURLs(let urls):
                    self.lastInputURLs = urls
                case .finished:
                    self.analysisTask = nil
                }
            }
        )
    }
}
