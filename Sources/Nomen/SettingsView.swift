import SwiftUI
import NomenCore

struct SettingsView: View {
    @AppStorage(AppPreferenceKey.appLanguage) private var languageRaw = AppLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.outputLanguage) private var outputLanguageRaw = OutputLanguageMode.followDocument.rawValue
    @AppStorage(AppPreferenceKey.namingInferenceBackend) private var inferenceRaw = NamingInferenceBackend.appleFoundation.rawValue
    @AppStorage(AppPreferenceKey.showPipelineDebug) private var showPipelineDebug = false
    @AppStorage(AppPreferenceKey.clearListAfterRename) private var clearListAfterRename = true

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }
    private var t: L10n { L10n(language) }

    var body: some View {
        Form {
            Section {
                PreferenceControls.AppLanguagePicker(languageRaw: $languageRaw)
            } header: {
                Label(t.settingsSectionAppLanguage, systemImage: "globe")
            }

            Section {
                PreferenceControls.OutputLanguagePicker(outputLanguageRaw: $outputLanguageRaw, t: t)
            } header: {
                Label(t.settingsSectionTitleLanguage, systemImage: "character.bubble")
            }

            Section {
                NamingModelSettingsBlock(inferenceRaw: $inferenceRaw, t: t)
            } header: {
                Label(t.settingsSectionNamingModel, systemImage: "cpu")
            }

            Section {
                PreferenceControls.ClearListAfterRenameToggle(
                    clearListAfterRename: $clearListAfterRename,
                    t: t
                )
            } header: {
                Label(t.settingsSectionWorkflow, systemImage: "checklist")
            }

            Section {
                PreferenceControls.PipelineDebugToggle(
                    showPipelineDebug: $showPipelineDebug,
                    t: t
                )
            } header: {
                Label(t.settingsSectionDeveloper, systemImage: "ant")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
