import Foundation

/// Einzelne Quelle für persistierte Einstellungen. Rohwerte bleiben unverändert,
/// damit vorhandene UserDefaults nach dem Refactor weitergelten.
enum AppPreferenceKey {
    static let onboardingCompleted = "nomen.onboardingCompleted"
    static let appLanguage = "nomen.appLanguage"
    static let outputLanguage = "nomen.outputLanguage"
    static let showPipelineDebug = "nomen.showPipelineDebug"
    static let namingInferenceBackend = "nomen.namingInferenceBackend"
    static let clearListAfterRename = "nomen.clearListAfterRename"
    static let lastLaunchedShortVersion = "nomen.lastLaunchedShortVersion"
}

enum AppPreferences {
    private static var defaults: UserDefaults { .standard }

    static var appLanguage: AppLanguage {
        let raw = defaults.string(forKey: AppPreferenceKey.appLanguage)
        return AppLanguage(rawValue: raw ?? AppLanguage.english.rawValue) ?? .english
    }

    /// Fehlt der Key (ältere Installationen), gilt wie bisher `true`.
    static var clearListAfterSuccessfulRename: Bool {
        if defaults.object(forKey: AppPreferenceKey.clearListAfterRename) == nil {
            return true
        }
        return defaults.bool(forKey: AppPreferenceKey.clearListAfterRename)
    }

    static var showPipelineDebug: Bool {
        defaults.bool(forKey: AppPreferenceKey.showPipelineDebug)
    }

    static var lastLaunchedShortVersion: String? {
        defaults.string(forKey: AppPreferenceKey.lastLaunchedShortVersion)
    }

    static func setLastLaunchedShortVersion(_ value: String) {
        defaults.set(value, forKey: AppPreferenceKey.lastLaunchedShortVersion)
    }

    static var onboardingCompletedIsUnset: Bool {
        defaults.object(forKey: AppPreferenceKey.onboardingCompleted) == nil
    }

    static func markOnboardingCompleted() {
        defaults.set(true, forKey: AppPreferenceKey.onboardingCompleted)
    }
}

enum NomenLog {
    static let subsystem = "nomen"
}
