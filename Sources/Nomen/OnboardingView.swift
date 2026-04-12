import AppKit
import SwiftUI

/// Erster Start: Willkommen und geführte Einrichtung (gleiche AppStorage-Keys wie Einstellungen).
struct OnboardingView: View {
    @AppStorage("nomen.onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("nomen.appLanguage") private var languageRaw = AppLanguage.english.rawValue
    @AppStorage("nomen.outputLanguage") private var outputLanguageRaw = OutputLanguageMode.followDocument.rawValue
    @AppStorage("nomen.namingInferenceBackend") private var inferenceRaw = NamingInferenceBackend.appleFoundation.rawValue
    @AppStorage("nomen.showPipelineDebug") private var showPipelineDebug = false
    @AppStorage("nomen.clearListAfterRename") private var clearListAfterRename = true

    @State private var phase: Phase = .welcome
    @State private var dismissOpacity: Double = 1
    @State private var isDismissing = false

    private enum Phase {
        case welcome
        case language
        case naming
        case more
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }

    /// Willkommensschritt: bevor die App-Sprache gewählt ist, System-Locale nutzen.
    private var welcomeT: L10n {
        L10n(Self.systemWelcomeLanguage())
    }

    private var t: L10n { L10n(appLanguage) }

    private let configStepCount = 3

    private var configStepProgressIndex: Int {
        switch phase {
        case .welcome: return 0
        case .language: return 1
        case .naming: return 2
        case .more: return 3
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 0) {
                    if phase != .welcome {
                        HStack {
                            Text(t.onboardingProgress(current: configStepProgressIndex, total: configStepCount))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.bottom, 10)

                        OnboardingStepProgressBar(fraction: Double(configStepProgressIndex) / Double(configStepCount))
                            .padding(.bottom, 18)
                    }

                    Group {
                        switch phase {
                        case .welcome:
                            welcomePanel
                        case .language:
                            languagePanel
                        case .naming:
                            namingPanel
                        case .more:
                            morePanel
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .padding(.vertical, 18)

                    footerButtons
                }
                .padding(28)
                .frame(width: 520, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )

                Spacer(minLength: 24)
            }
        }
        .opacity(dismissOpacity)
        .allowsHitTesting(!isDismissing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(welcomeT.onboardingWelcomeTitle)
                        .font(.title2.weight(.semibold))
                    Text(welcomeT.onboardingWelcomeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingChoiceButton(
                    title: welcomeT.onboardingStartNow,
                    subtitle: welcomeT.onboardingStartNowHint,
                    systemImage: "bolt.fill"
                ) {
                    finishOnboarding()
                }
                .disabled(isDismissing)

                OnboardingChoiceButton(
                    title: welcomeT.onboardingConfigure,
                    subtitle: welcomeT.onboardingConfigureHint,
                    systemImage: "slider.horizontal.3",
                    style: .secondary
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        phase = .language
                    }
                }
                .disabled(isDismissing)
            }
            .padding(.top, 8)
        }
    }

    private var languagePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                icon: "globe",
                title: t.onboardingStepLanguageTitle,
                subtitle: t.onboardingStepLanguageSubtitle
            )

            VStack(alignment: .leading, spacing: 14) {
                Label(t.settingsSectionAppLanguage, systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
                Picker(selection: $languageRaw, label: EmptyView()) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Label(t.settingsSectionTitleLanguage, systemImage: "character.bubble")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
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
    }

    private var namingPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                icon: "cpu",
                title: t.onboardingStepNamingTitle,
                subtitle: t.onboardingStepNamingSubtitle
            )

            Label(t.settingsSectionNamingModel, systemImage: "cpu")
                .font(.subheadline.weight(.semibold))

            NamingModelSettingsBlock(inferenceRaw: $inferenceRaw, t: t)
        }
    }

    private var morePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                icon: "checklist",
                title: t.onboardingStepMoreTitle,
                subtitle: t.onboardingStepMoreSubtitle
            )

            Toggle(isOn: $clearListAfterRename) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.settingsClearListAfterRename)
                    Text(t.settingsClearListAfterRenameHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $showPipelineDebug) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.debugPipelineToggle)
                    Text(t.debugPipelineHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 4)
        }
    }

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        HStack(spacing: 10) {
            if phase != .welcome {
                Button(t.onboardingBack) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        switch phase {
                        case .welcome: break
                        case .language: phase = .welcome
                        case .naming: phase = .language
                        case .more: phase = .naming
                        }
                    }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isDismissing)
            }

            Spacer(minLength: 8)

            if phase == .more {
                Button(t.onboardingFinish) {
                    finishOnboarding()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnboardingProminentButtonStyle())
                .disabled(isDismissing)
            } else if phase != .welcome {
                Button(t.onboardingNext) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        switch phase {
                        case .welcome: break
                        case .language: phase = .naming
                        case .naming: phase = .more
                        case .more: break
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnboardingProminentButtonStyle())
                .disabled(isDismissing)
            }
        }
    }

    private func finishOnboarding() {
        guard !isDismissing else { return }
        isDismissing = true
        let n = NamingInferenceBackend.normalizedInferenceStorageRawValue(inferenceRaw)
        if n != inferenceRaw { inferenceRaw = n }
        withAnimation(.easeOut(duration: 0.55)) {
            dismissOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(580))
            onboardingCompleted = true
        }
    }

    private static func systemWelcomeLanguage() -> AppLanguage {
        guard let code = Locale.current.language.languageCode?.identifier else { return .english }
        if code == "de" { return .german }
        return .english
    }
}

// MARK: - Subviews

private struct OnboardingStepProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

private struct OnboardingChoiceButton: View {
    enum Style { case primary, secondary }

    var title: String
    var subtitle: String
    var systemImage: String
    var style: Style = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(style == .primary ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style == .primary ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        style == .primary ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(isEnabled ? 1 : 0.35))
            )
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.85))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}
