import Foundation
import NomenCore

extension L10n {
    // MARK: - Onboarding

    var onboardingWelcomeTitle: String {
        s(en: "Welcome to Nomen", de: "Willkommen bei Nomen")
    }

    var onboardingWelcomeSubtitle: String {
        s(
            en: "Rename documents locally with on-device AI — private, no cloud for naming.",
            de: "Benenne Dokumente lokal mit On-Device-KI — privat, ohne Cloud für die Benennung."
        )
    }

    var onboardingStartNow: String {
        s(en: "Start now", de: "Direkt starten")
    }

    var onboardingStartNowHint: String {
        s(
            en: "Keeps recommended defaults. You can change everything later in Settings.",
            de: "Behält sinnvolle Standardwerte. Alles ist später in den Einstellungen änderbar."
        )
    }

    var onboardingConfigure: String {
        s(en: "Set up step by step", de: "Schritt für Schritt einrichten")
    }

    var onboardingConfigureHint: String {
        s(
            en: "Language, naming model, and a few workflow options.",
            de: "Sprache, Benennungs-Modell und ein paar Workflow-Optionen."
        )
    }

    var onboardingStepLanguageTitle: String {
        s(en: "Language", de: "Sprache")
    }

    var onboardingStepLanguageSubtitle: String {
        s(
            en: "How the app speaks to you and how archive titles are written.",
            de: "Wie die App dir angezeigt wird und wie Archivtitel formuliert werden."
        )
    }

    var onboardingStepNamingTitle: String {
        s(en: "Naming model", de: "Benennungs-Modell")
    }

    var onboardingStepNamingSubtitle: String {
        s(
            en: "Apple’s model is ready to use but slower and less exact; Qwen is faster and sharper after a download.",
            de: "Apples Modell ist sofort nutzbar, aber langsamer und weniger exakt; Qwen ist nach dem Download schneller und in der Regel treffsicherer."
        )
    }

    var onboardingStepMoreTitle: String {
        s(en: "Workflow & developer", de: "Workflow & Entwickler")
    }

    var onboardingStepMoreSubtitle: String {
        s(
            en: "Optional: clear the list after rename and pipeline debug for troubleshooting.",
            de: "Optional: Liste nach Umbenennen leeren und Pipeline-Debug zur Fehlersuche."
        )
    }

    var onboardingBack: String { s(en: "Back", de: "Zurück") }

    var onboardingNext: String { s(en: "Continue", de: "Weiter") }

    var onboardingFinish: String { s(en: "Done", de: "Fertig") }

    func onboardingProgress(current: Int, total: Int) -> String {
        s(en: "Step \(current) of \(total)", de: "Schritt \(current) von \(total)")
    }

}
