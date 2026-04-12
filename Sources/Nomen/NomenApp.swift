import AppKit
import SwiftUI

@main
struct NomenApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 760, minHeight: 540)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(aboutMenuTitle) {
                    let lang = currentAppLanguage()
                    let t = L10n(lang)
                    let creditsText = "\(t.aboutCopyright)\n\n\(t.aboutCredits)"
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Nomen",
                            .applicationVersion: Bundle.main.shortVersion,
                            .version: "Build \(Bundle.main.buildVersion)",
                            .credits: NSAttributedString(
                                string: creditsText,
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                    .foregroundColor: NSColor.secondaryLabelColor,
                                ]
                            ),
                        ]
                    )
                }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }

    private var aboutMenuTitle: String {
        L10n(currentAppLanguage()).aboutMenu
    }

    private func currentAppLanguage() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "nomen.appLanguage")
        return AppLanguage(rawValue: raw ?? AppLanguage.english.rawValue) ?? .english
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var buildVersion: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}
