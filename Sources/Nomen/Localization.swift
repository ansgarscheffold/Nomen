import Foundation
import NomenCore

struct L10n: Sendable {
    var lang: AppLanguage

    init(_ lang: AppLanguage) {
        self.lang = lang
    }

    func s(en: String, de: String) -> String {
        switch lang {
        case .english: return en
        case .german: return de
        }
    }
}
