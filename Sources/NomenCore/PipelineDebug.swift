import Foundation

/// Step-by-step trace for one file (optional; filled when debug is enabled in Settings).
public struct PipelineDebugSnapshot: Hashable {
    /// Human-readable: source lengths and which text was chosen for the model.
    public var extractionSummary: String
    public var embeddedPDFCharacterCount: Int?
    public var ocrCharacterCount: Int?
    public var chosenSourceLabel: String

    /// Text the model sees (may be truncated in UI vs. actual prompt cap).
    public var textSampleForModel: String
    public var textTotalCharacters: Int

    public var modelRawReply: String?
    public var jsonSuggestedTitle: String?
    public var jsonDocumentDateISO: String?
    public var jsonDateFromDocument: Bool?
    public var modelOrParseError: String?

    public var finalTitleAfterSanitize: String
    public var usedContentDate: Bool
    public var usedFilenameFallbackForTitle: Bool

    public init(
        extractionSummary: String,
        embeddedPDFCharacterCount: Int?,
        ocrCharacterCount: Int?,
        chosenSourceLabel: String,
        textSampleForModel: String,
        textTotalCharacters: Int,
        modelRawReply: String?,
        jsonSuggestedTitle: String?,
        jsonDocumentDateISO: String?,
        jsonDateFromDocument: Bool?,
        modelOrParseError: String?,
        finalTitleAfterSanitize: String,
        usedContentDate: Bool,
        usedFilenameFallbackForTitle: Bool
    ) {
        self.extractionSummary = extractionSummary
        self.embeddedPDFCharacterCount = embeddedPDFCharacterCount
        self.ocrCharacterCount = ocrCharacterCount
        self.chosenSourceLabel = chosenSourceLabel
        self.textSampleForModel = textSampleForModel
        self.textTotalCharacters = textTotalCharacters
        self.modelRawReply = modelRawReply
        self.jsonSuggestedTitle = jsonSuggestedTitle
        self.jsonDocumentDateISO = jsonDocumentDateISO
        self.jsonDateFromDocument = jsonDateFromDocument
        self.modelOrParseError = modelOrParseError
        self.finalTitleAfterSanitize = finalTitleAfterSanitize
        self.usedContentDate = usedContentDate
        self.usedFilenameFallbackForTitle = usedFilenameFallbackForTitle
    }
}

public extension PipelineDebugSnapshot {
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

public struct PipelineDebugL10n {
    public var step1: String
    public var step2: String
    public var step3: String
    public var step4: String
    public var step5: String
    public var embeddedChars: String
    public var ocrChars: String
    public var chosen: String
    public var totalChars: String
    public var error: String
    public var titleUsed: String
    public var dateFromDoc: String
    public var fallbackStem: String
    public var yes: String
    public var no: String

    public init(
        step1: String,
        step2: String,
        step3: String,
        step4: String,
        step5: String,
        embeddedChars: String,
        ocrChars: String,
        chosen: String,
        totalChars: String,
        error: String,
        titleUsed: String,
        dateFromDoc: String,
        fallbackStem: String,
        yes: String,
        no: String
    ) {
        self.step1 = step1
        self.step2 = step2
        self.step3 = step3
        self.step4 = step4
        self.step5 = step5
        self.embeddedChars = embeddedChars
        self.ocrChars = ocrChars
        self.chosen = chosen
        self.totalChars = totalChars
        self.error = error
        self.titleUsed = titleUsed
        self.dateFromDoc = dateFromDoc
        self.fallbackStem = fallbackStem
        self.yes = yes
        self.no = no
    }
}
