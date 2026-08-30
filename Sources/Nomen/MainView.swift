import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NomenCore

struct MainView: View {
    @StateObject private var model = RenameViewModel()
    @StateObject private var quickLook = QuickLookCoordinator()
    @State private var tableSelection: Set<RenamePreviewRow.ID> = []
    @State private var isDragTargeted = false
    @FocusState private var tableKeyboardFocused: Bool
    @AppStorage(AppPreferenceKey.onboardingCompleted) private var onboardingCompleted = false
    @State private var mainChromeOpacity: Double = 1
    @AppStorage(AppPreferenceKey.appLanguage) private var languageRaw = AppLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.outputLanguage) private var outputLanguageRaw = OutputLanguageMode.followDocument.rawValue
    @AppStorage(AppPreferenceKey.showPipelineDebug) private var showPipelineDebug = false
    @AppStorage(AppPreferenceKey.namingInferenceBackend) private var inferenceRaw = NamingInferenceBackend.appleFoundation.rawValue

    private var lang: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }

    private var t: L10n { L10n(lang) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                namingBar
                Divider()
                toolbarRow
                Divider()
                dropZone
                Divider()
                previewTable
                if showPipelineDebug {
                    Divider()
                    pipelineDebugPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(mainChromeOpacity)

            if !onboardingCompleted {
                OnboardingView()
                    .zIndex(1)
            }
        }
        .onAppear {
            applyOnboardingUpgradeMigrationIfNeeded()
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                mainChromeOpacity = onboardingCompleted ? 1 : 0.88
            }
            let normalizedInference = NamingInferenceBackend.normalizedInferenceStorageRawValue(inferenceRaw)
            if normalizedInference != inferenceRaw {
                inferenceRaw = normalizedInference
            }
            model.uiLanguage = lang
            model.outputLanguageMode = OutputLanguageMode(rawValue: outputLanguageRaw) ?? .followDocument
            model.namingInferenceBackend = NamingInferenceBackend(rawValue: inferenceRaw) ?? .appleFoundation
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if model.namingInferenceBackend == .appleFoundation {
                    FoundationModelPrewarm.prewarmOnceIfAvailable()
                }
            }
            #endif
        }
        .onChange(of: languageRaw) { _, _ in
            model.uiLanguage = lang
            model.syncFooterAfterLanguageChange()
        }
        .onChange(of: outputLanguageRaw) { _, newVal in
            model.outputLanguageMode = OutputLanguageMode(rawValue: newVal) ?? .followDocument
        }
        .onChange(of: inferenceRaw) { _, newVal in
            let backend = NamingInferenceBackend(rawValue: newVal) ?? .appleFoundation
            model.namingInferenceBackend = backend
            if backend != .llamaQwenGGUF {
                Task { await LlamaCppRunner.shared.unload() }
            }
        }
        .onChange(of: model.schema) { _, _ in
            model.refreshAfterSchemaChange()
        }
        .onChange(of: model.rows) { _, newRows in
            let valid = Set(newRows.map(\.id))
            tableSelection = tableSelection.intersection(valid)
        }
        .onChange(of: tableSelection) { _, newSel in
            if !newSel.isEmpty {
                tableKeyboardFocused = true
            }
        }
        .onChange(of: onboardingCompleted) { _, done in
            guard done else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                mainChromeOpacity = 1
            }
        }
    }

    private var namingBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(t.namingPattern)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()

            Picker("", selection: $model.schema) {
                ForEach(DateNameSchema.allCases) { s in
                    Text(t.schemaMenuLabel(s)).tag(s)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 220, alignment: .leading)
            .disabled(model.isBusy || model.isRenaming)

            Text(t.schemaDetailHint(model.schema))
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            Label(t.localOnlyBadge, systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)

            Spacer(minLength: 8)

            if model.isRenaming {
                renameToolbarFeedback
                    .frame(minWidth: 100, maxWidth: 440, alignment: .leading)
            } else if model.isBusy {
                HStack(alignment: .center, spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.progressLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 100, maxWidth: 360, alignment: .leading)
                    ProgressView(value: model.progressValue)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .frame(minWidth: 140, idealWidth: 260, maxWidth: 340, alignment: .center)
                    Button(action: { model.stopAnalysis() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.stop)
                    .accessibilityLabel(t.stop)
                }
            } else if model.phase == .ready, !model.rows.isEmpty {
                Text(model.progressLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(role: .destructive, action: { model.clear() }) {
                Label(t.clear, systemImage: "trash")
            }
            .disabled(model.rows.isEmpty || model.isBusy)

            Button(action: { model.renameAll() }) {
                Label(t.renameAll, systemImage: "textformat")
            }
            .buttonStyle(GentleProminentButtonStyle())
            .disabled(!model.canRename)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDragTargeted
                      ? Color.accentColor.opacity(0.08)
                      : Color.primary.opacity(0.03))
                .animation(.easeInOut(duration: 0.18), value: isDragTargeted)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.30),
                    style: StrokeStyle(lineWidth: isDragTargeted ? 2.5 : 1.5, dash: [9, 6])
                )
                .animation(.easeInOut(duration: 0.18), value: isDragTargeted)

            HStack(spacing: 14) {
                Image(systemName: isDragTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 26, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDragTargeted ? Color.accentColor : .secondary)
                    .animation(.easeInOut(duration: 0.18), value: isDragTargeted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(t.dropHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isDragTargeted ? Color.accentColor : .primary)
                    Text(t.dropSubline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !model.isRenaming else { return }
            presentOpenPanel()
        }
        .onDrop(of: [.fileURL, .url], isTargeted: $isDragTargeted) { providers in
            guard !model.isRenaming else { return false }
            Task { @MainActor in
                let urls = await DroppedFileURLCollector.collect(from: providers)
                if urls.isEmpty {
                    model.errorMessage = t.dropCouldNotReadURLs
                    return
                }
                model.addFiles(urls: urls)
            }
            return true
        }
    }

    private var previewTable: some View {
        Group {
            if let err = model.errorMessage {
                ContentUnavailableView(
                    t.emptyErrorTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                ContentUnavailableView(
                    t.emptyNoFilesTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(t.emptyNoFilesDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.rows, selection: $tableSelection) {
                    TableColumn(t.columnOldName) { row in
                        Text(row.originalName)
                            .lineLimit(2)
                            .foregroundStyle(row.isAnalysisPlaceholder ? .secondary : .primary)
                            .italic(row.isAnalysisPlaceholder)
                    }
                    .width(min: 200, ideal: 300, max: .infinity)

                    TableColumn(t.columnNewName) { row in
                        Text(row.proposedName)
                            .font(row.isAnalysisPlaceholder ? .body : .body.weight(.semibold))
                            .lineLimit(2)
                            .foregroundStyle(row.isAnalysisPlaceholder ? .secondary : .primary)
                            .italic(row.isAnalysisPlaceholder)
                    }
                    .width(min: 220, ideal: 380, max: .infinity)

                    TableColumn(t.columnHint) { row in
                        if let msg = row.statusMessage, !row.isAnalysisPlaceholder {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(row.usedFallbackDate ? .orange : .secondary)
                                .lineLimit(2)
                        }
                    }
                    .width(min: 100, ideal: 200, max: .infinity)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .focusable()
                .focused($tableKeyboardFocused)
                .onKeyPress(.space, phases: .down) { _ in
                    guard !tableSelection.isEmpty else { return .ignored }
                    openQuickLookForSelection()
                    return .handled
                }
                .contextMenu(forSelectionType: RenamePreviewRow.ID.self) { ids in
                    if !ids.isEmpty {
                        let ready = ids.allSatisfy { id in
                            model.rows.first(where: { $0.id == id })?.isAnalysisPlaceholder == false
                        }
                        Button {
                            model.renameRows(ids: ids)
                        } label: {
                            Label(t.contextRenameSelected, systemImage: "pencil")
                        }
                        .disabled(!ready || model.isBusy || model.isRenaming)

                        if ids.count == 1, let id = ids.first,
                           let row = model.rows.first(where: { $0.id == id }) {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([row.sourceURL])
                            } label: {
                                Label(t.contextShowInFinder, systemImage: "folder")
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            model.removeRows(ids: ids)
                        } label: {
                            Label(t.contextRemoveFromList, systemImage: "minus.circle")
                        }

                        Divider()
                    }

                    Button(role: .destructive) {
                        model.clear()
                    } label: {
                        Label(t.clear, systemImage: "trash")
                    }
                    .disabled(model.rows.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var renameToolbarFeedback: some View {
        switch model.renameFeedbackPhase {
        case .idle:
            EmptyView()
        case .working(let done, let total):
            HStack(alignment: .center, spacing: 10) {
                if done == 0 {
                    ProgressView()
                        .controlSize(.small)
                    Text(t.renameWorkingPreparing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    ProgressView(value: Double(done), total: Double(total))
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)
                    Text(t.renameWorkingProgress(done: done, total: total))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .outcome(let kind, let renamedCount, let entireList):
            HStack(alignment: .center, spacing: 8) {
                switch kind {
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: model.renameFeedbackPhase)
                    Text(t.renameSuccessSummary(count: renamedCount, entireList: entireList))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                case .partialFailure:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(t.renamePartialTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                case .allFailed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(t.renameAllFailedTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var pipelineDebugPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t.debugInspectorTitle)
                .font(.subheadline.weight(.semibold))

            if tableSelection.count != 1 {
                Text(t.debugInspectorHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let id = tableSelection.first,
                      let row = model.rows.first(where: { $0.id == id }) {
                if let dbg = row.pipelineDebug {
                    ScrollView {
                        Text(verbatim: dbg.formattedReport(localizedHeaders: t.pipelineDebugHeaders))
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160, maxHeight: 320)
                } else {
                    Text(t.debugInspectorNoData)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35))
    }

    private func openQuickLookForSelection() {
        guard !tableSelection.isEmpty else { return }
        let ids = tableSelection
        let urls = model.rows
            .filter { ids.contains($0.id) }
            .map(\.sourceURL)
        guard !urls.isEmpty else { return }
        quickLook.show(urls: urls)
    }

    /// Neue Installation: Onboarding anzeigen. App-Update von einer Version ohne Onboarding: einmalig als erledigt markieren.
    private func applyOnboardingUpgradeMigrationIfNeeded() {
        let last = AppPreferences.lastLaunchedShortVersion
        let current =
            (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        defer { AppPreferences.setLastLaunchedShortVersion(current) }

        guard AppPreferences.onboardingCompletedIsUnset else { return }
        if let last, last != current {
            AppPreferences.markOnboardingCompleted()
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = t.openPanelPrompt
        panel.allowedContentTypes = SupportedDocumentFormat.openPanelContentTypes

        panel.begin { response in
            guard response == .OK else { return }
            model.addFiles(urls: panel.urls)
        }
    }
}

private struct GentleProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(isEnabled ? 1 : 0.35))
            )
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.85))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
            .opacity(configuration.isPressed && isEnabled ? 0.92 : (isEnabled ? 1 : 0.55))
    }
}
