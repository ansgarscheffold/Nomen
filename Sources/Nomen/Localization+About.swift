import Foundation
import NomenCore

extension L10n {
    // MARK: - About / App menu

    var aboutMenu: String { s(en: "About Nomen…", de: "Über Nomen…") }

    var aboutCopyright: String {
        "© 2026 Dr. med. Ansgar Scheffold"
    }

    var aboutCredits: String {
        s(
            en: """
            PDFs with embedded text (digital invoices etc.) are read directly via PDFKit (up to 40 pages). \
            Scanned PDFs fall back to Vision OCR on the first page. Other file types: PDFKit or plain text. \
            Naming uses either Apple’s on-device Foundation Models (Apple Intelligence, macOS 26+) or an optional local GGUF model (Qwen2.5-7B via llama.cpp), chosen in Settings.

            Everything runs locally — no cloud API calls for naming; the GGUF is downloaded once if you enable it. \
            .docx is read locally via ZIP/XML extraction. Legacy .doc is not supported.
            """,
            de: """
            PDFs mit eingebettetem Text (digitale Rechnungen usw.) werden direkt via PDFKit gelesen (bis zu 40 Seiten). \
            Gescannte PDFs nutzen Vision-OCR auf der ersten Seite als Fallback. Andere Dateitypen: PDFKit oder Klartext. \
            Benennung entweder mit Apples On-Device Foundation Models (Apple Intelligence, macOS 26+) oder optional mit einem lokalen GGUF-Modell (Qwen2.5-7B via llama.cpp), wählbar in den Einstellungen.

            Alles läuft lokal — keine Cloud-APIs für die Benennung; das GGUF wird bei Bedarf einmal heruntergeladen. \
            .docx wird lokal via ZIP/XML-Extraktion gelesen. Klassisches .doc wird nicht unterstützt.
            """
        )
    }

}
