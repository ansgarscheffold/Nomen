import Foundation

/// Step-by-step trace for one file (optional; filled when debug is enabled in Settings).
struct PipelineDebugSnapshot: Hashable {
    /// Human-readable: source lengths and which text was chosen for the model.
    var extractionSummary: String
    var embeddedPDFCharacterCount: Int?
    var ocrCharacterCount: Int?
    var chosenSourceLabel: String

    /// Text the model sees (may be truncated in UI vs. actual prompt cap).
    var textSampleForModel: String
    var textTotalCharacters: Int

    var modelRawReply: String?
    var jsonSuggestedTitle: String?
    var jsonDocumentDateISO: String?
    var jsonDateFromDocument: Bool?
    var modelOrParseError: String?

    var finalTitleAfterSanitize: String
    var usedContentDate: Bool
    var usedFilenameFallbackForTitle: Bool
}

extension PipelineDebugSnapshot {
    func formattedReport(localizedHeaders: PipelineDebugL10n) -> String {
        var lines: [String] = []
        lines.append("━━ \(localizedHeaders.step1) ━━")
        lines.append(extractionSummary)
        if let e = embeddedPDFCharacterCount {
            lines.append("\(localizedHeaders.embeddedChars): \(e)")
        }
        if let o = ocrCharacterCount {
            lines.append("\(localizedHeaders.ocrChars): \(o)")
        }
        lines.append("\(localizedHeaders.chosen): \(chosenSourceLabel)")
        lines.append("")
        lines.append("━━ \(localizedHeaders.step2) ━━")
        lines.append("\(localizedHeaders.totalChars): \(textTotalCharacters)")
        lines.append(textSampleForModel)
        lines.append("")
        lines.append("━━ \(localizedHeaders.step3) ━━")
        lines.append(modelRawReply ?? "—")
        lines.append("")
        lines.append("━━ \(localizedHeaders.step4) ━━")
        if let err = modelOrParseError, !err.isEmpty {
            lines.append("\(localizedHeaders.error): \(err)")
        }
        lines.append("suggestedTitle (JSON): \(jsonSuggestedTitle ?? "—")")
        lines.append("documentDateISO (JSON): \(jsonDocumentDateISO ?? "—")")
        lines.append("dateFromDocument (JSON): \(jsonDateFromDocument.map { String($0) } ?? "—")")
        lines.append("")
        lines.append("━━ \(localizedHeaders.step5) ━━")
        lines.append("\(localizedHeaders.titleUsed): \(finalTitleAfterSanitize)")
        lines.append("\(localizedHeaders.dateFromDoc): \(usedContentDate ? localizedHeaders.yes : localizedHeaders.no)")
        lines.append("\(localizedHeaders.fallbackStem): \(usedFilenameFallbackForTitle ? localizedHeaders.yes : localizedHeaders.no)")
        return lines.joined(separator: "\n")
    }
}

struct PipelineDebugL10n {
    var step1: String
    var step2: String
    var step3: String
    var step4: String
    var step5: String
    var embeddedChars: String
    var ocrChars: String
    var chosen: String
    var totalChars: String
    var error: String
    var titleUsed: String
    var dateFromDoc: String
    var fallbackStem: String
    var yes: String
    var no: String
}
