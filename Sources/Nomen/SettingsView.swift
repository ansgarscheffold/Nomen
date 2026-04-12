import SwiftUI

struct SettingsView: View {
    @AppStorage("nomen.appLanguage") private var languageRaw = AppLanguage.english.rawValue
    @AppStorage("nomen.outputLanguage") private var outputLanguageRaw = OutputLanguageMode.followDocument.rawValue
    @AppStorage("nomen.namingInferenceBackend") private var inferenceRaw = NamingInferenceBackend.appleFoundation.rawValue
    @AppStorage("nomen.showPipelineDebug") private var showPipelineDebug = false
    @AppStorage("nomen.clearListAfterRename") private var clearListAfterRename = true

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }
    private var t: L10n { L10n(language) }

    var body: some View {
        Form {
            // ── App language ─────────────────────────────────────────────────
            Section {
                Picker(selection: $languageRaw, label: EmptyView()) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Label(t.settingsSectionAppLanguage, systemImage: "globe")
            }

            // ── Title language ────────────────────────────────────────────────
            Section {
                Picker(selection: $outputLanguageRaw, label: EmptyView()) {
                    ForEach(OutputLanguageMode.allCases) { mode in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.outputLanguageModeLabel(mode))
                            Text(t.outputLanguageHint(mode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Label(t.settingsSectionTitleLanguage, systemImage: "character.bubble")
            }

            // ── Benennungs-Modell ─────────────────────────────────────────────
            Section {
                NamingModelSettingsBlock(inferenceRaw: $inferenceRaw, t: t)
            } header: {
                Label(t.settingsSectionNamingModel, systemImage: "cpu")
            }

            // ── Nach Umbenennen ───────────────────────────────────────────────
            Section {
                Toggle(isOn: $clearListAfterRename) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.settingsClearListAfterRename)
                        Text(t.settingsClearListAfterRenameHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label(t.settingsSectionWorkflow, systemImage: "checklist")
            }

            // ── Developer ─────────────────────────────────────────────────────
            Section {
                Toggle(isOn: $showPipelineDebug) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.debugPipelineToggle)
                        Text(t.debugPipelineHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label(t.settingsSectionDeveloper, systemImage: "ant")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
