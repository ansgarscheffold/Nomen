import Foundation
import NomenCore

extension L10n {
    // MARK: - Schema

    func schemaMenuLabel(_ schema: DateNameSchema) -> String {
        switch schema {
        case .yearMonthTitle:
            return s(en: "YYYY MM + title", de: "YYYY MM + Titel")
        case .compactDateTitle:
            return s(en: "YYMMDD + title", de: "YYMMDD + Titel")
        case .titleOnly:
            return s(en: "Title only", de: "Nur Titel")
        }
    }

    func schemaDetailHint(_ schema: DateNameSchema) -> String {
        switch schema {
        case .yearMonthTitle:
            return s(en: "e.g. “2026 04 Invoice iPhone”", de: "z. B. „2026 04 Rechnung iPhone“")
        case .compactDateTitle:
            return s(en: "e.g. “260410 Invoice iPhone”", de: "z. B. „260410 Rechnung iPhone“")
        case .titleOnly:
            return s(en: "e.g. “Invoice iPhone”", de: "z. B. „Rechnung iPhone“")
        }
    }

}
