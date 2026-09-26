import SwiftUI
import NomenCore

/// Wiederverwendbare Preference-Controls für Settings und Onboarding.
enum PreferenceControls {
    struct AppLanguagePicker: View {
        @Binding var languageRaw: String

        var body: some View {
            Picker(selection: $languageRaw, label: EmptyView()) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    struct OutputLanguagePicker: View {
        @Binding var outputLanguageRaw: String
        let t: L10n

        var body: some View {
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
        }
    }

    struct ClearListAfterRenameToggle: View {
        @Binding var clearListAfterRename: Bool
        let t: L10n

        var body: some View {
            Toggle(isOn: $clearListAfterRename) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.settingsClearListAfterRename)
                    Text(t.settingsClearListAfterRenameHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    struct PipelineDebugToggle: View {
        @Binding var showPipelineDebug: Bool
        let t: L10n

        var body: some View {
            Toggle(isOn: $showPipelineDebug) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.debugPipelineToggle)
                    Text(t.debugPipelineHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
