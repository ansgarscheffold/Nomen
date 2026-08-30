import Foundation

/// Einzelne Quelle für persistierte Einstellungen. Rohwerte bleiben unverändert,
/// damit vorhandene UserDefaults nach dem Refactor weitergelten.
public enum AppPreferenceKey {
    public static let onboardingCompleted = "nomen.onboardingCompleted"
    public static let appLanguage = "nomen.appLanguage"
    public static let outputLanguage = "nomen.outputLanguage"
    public static let showPipelineDebug = "nomen.showPipelineDebug"
    public static let namingInferenceBackend = "nomen.namingInferenceBackend"
    public static let clearListAfterRename = "nomen.clearListAfterRename"
    public static let lastLaunchedShortVersion = "nomen.lastLaunchedShortVersion"
}

public enum AppPreferences {
    private static var defaults: UserDefaults { .standard }

    public static var appLanguage: AppLanguage {
        let raw = defaults.string(forKey: AppPreferenceKey.appLanguage)
        return AppLanguage(rawValue: raw ?? AppLanguage.english.rawValue) ?? .english
    }

    /// Fehlt der Key (ältere Installationen), gilt wie bisher `true`.
    public static var clearListAfterSuccessfulRename: Bool {
        if defaults.object(forKey: AppPreferenceKey.clearListAfterRename) == nil {
            return true
        }
        return defaults.bool(forKey: AppPreferenceKey.clearListAfterRename)
    }

    public static var showPipelineDebug: Bool {
        defaults.bool(forKey: AppPreferenceKey.showPipelineDebug)
    }

    public static var lastLaunchedShortVersion: String? {
        defaults.string(forKey: AppPreferenceKey.lastLaunchedShortVersion)
    }

    public static func setLastLaunchedShortVersion(_ value: String) {
        defaults.set(value, forKey: AppPreferenceKey.lastLaunchedShortVersion)
    }

    public static var onboardingCompletedIsUnset: Bool {
        defaults.object(forKey: AppPreferenceKey.onboardingCompleted) == nil
    }

    public static func markOnboardingCompleted() {
        defaults.set(true, forKey: AppPreferenceKey.onboardingCompleted)
    }
}

public enum NomenLog {
    public static let subsystem = "nomen"
}
