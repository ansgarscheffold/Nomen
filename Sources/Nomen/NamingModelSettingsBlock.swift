import AppKit
import SwiftUI
import NomenCore

/// Gemeinsamer Block: Benennungs-Backend inkl. GGUF-Download (Einstellungen + Onboarding).
struct NamingModelSettingsBlock: View {
    @Binding var inferenceRaw: String
    let t: L10n

    @State private var showGgufDownloadConfirm = false
    @State private var isDownloadingGguf = false
    @State private var ggufDownloadFraction: Double?
    @State private var ggufDownloadError: String?

    private var inferenceBackend: NamingInferenceBackend {
        NamingInferenceBackend(rawValue: inferenceRaw) ?? .appleFoundation
    }

    var body: some View {
        Group {
            Picker(selection: $inferenceRaw, label: EmptyView()) {
                ForEach(NamingInferenceBackend.allCases) { backend in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.namingInferenceLabel(backend))
                        Text(t.namingInferenceHint(backend))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tag(backend.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if inferenceBackend == .llamaQwenGGUF {
                if QwenGGUFModelSupport.isDownloaded {
                    Label(t.ggufDownloadedLabel, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Button(t.ggufRevealInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting(QwenGGUFModelSupport.allLocalShardURLs)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showGgufDownloadConfirm = true
                        } label: {
                            if isDownloadingGguf {
                                Label(t.ggufDownloading, systemImage: "arrow.down.circle")
                            } else {
                                Label(t.ggufDownloadButton, systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isDownloadingGguf)

                        if isDownloadingGguf {
                            ProgressView(value: ggufDownloadFraction ?? 0)
                                .progressViewStyle(.linear)
                            Text(
                                ggufDownloadFraction.map { f in
                                    t.ggufDownloadProgressPercent(Int((f * 100).rounded(.down)))
                                } ?? t.ggufDownloading
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .confirmationDialog(t.ggufDownloadConfirmTitle, isPresented: $showGgufDownloadConfirm, titleVisibility: .visible) {
            Button(t.ggufDownloadButton) {
                Task { await runGgufDownload() }
            }
            Button(t.dialogCancel, role: .cancel) {}
        } message: {
            Text(t.ggufDownloadConfirmMessage)
        }
        .alert(
            t.alertErrorTitle,
            isPresented: Binding(
                get: { ggufDownloadError != nil },
                set: { if !$0 { ggufDownloadError = nil } }
            )
        ) {
            Button(t.dialogOK, role: .cancel) { ggufDownloadError = nil }
        } message: {
            Text(ggufDownloadError ?? "")
        }
        .onAppear {
            let n = NamingInferenceBackend.normalizedInferenceStorageRawValue(inferenceRaw)
            if n != inferenceRaw { inferenceRaw = n }
        }
    }

    @MainActor
    private func runGgufDownload() async {
        isDownloadingGguf = true
        ggufDownloadFraction = nil
        ggufDownloadError = nil
        defer {
            isDownloadingGguf = false
            ggufDownloadFraction = nil
        }
        do {
            try QwenGGUFModelSupport.ensureModelsDirectoryExists()
            QwenGGUFModelSupport.resetIntegrityCache()
            let shards = QwenGGUFCatalog.shards
            let total = Double(shards.count)
            for (index, shard) in shards.enumerated() {
                guard let remote = QwenGGUFCatalog.downloadURL(forShardFileName: shard.fileName) else {
                    throw GgufModelDownloadError.disallowedHost
                }
                try await GgufModelDownload.download(
                    from: remote,
                    to: QwenGGUFModelSupport.localURL(forShardFileName: shard.fileName),
                    expectedByteCount: shard.byteCount,
                    expectedSHA256Hex: shard.sha256Hex,
                    onProgress: { fraction in
                        let base = Double(index) / total
                        if let fraction {
                            ggufDownloadFraction = base + fraction / total
                        } else {
                            ggufDownloadFraction = nil
                        }
                    }
                )
            }
        } catch {
            ggufDownloadError = t.ggufDownloadFailed(error.localizedDescription)
        }
    }
}
