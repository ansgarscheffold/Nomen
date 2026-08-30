import Foundation
import NomenCore

@main
enum NomenCoreChecks {
    static func main() {
        var failed = 0
        func check(_ name: String, _ ok: () -> Bool) {
            if ok() {
                print("ok  \(name)")
            } else {
                failed += 1
                print("FAIL \(name)")
            }
        }

        check("slug keeps umlauts") {
            FilenameSanitizer.slugTitle("Überweisung Straße") == "Überweisung Straße"
        }
        check("slug collapses punctuation") {
            FilenameSanitizer.slugTitle("Rechnung — iPhone_2024") == "Rechnung iPhone 2024"
        }
        check("clean stem strips ISO date") {
            FilenameSanitizer.cleanStemForTitle("2026 04 10 01 33 Doc") == "Doc"
        }
        check("clean stem strips YYMMDD") {
            FilenameSanitizer.cleanStemForTitle("231215 Hausratversicherung") == "Hausratversicherung"
        }
        check("clean stem drops digit tokens") {
            let cleaned = FilenameSanitizer.cleanStemForTitle("Apple Support Case 102866598713 11_4_2026_1_24pm")
            return cleaned.contains("Apple Support Case") && !cleaned.contains("102866598713")
        }
        check("archive fallback") {
            FilenameSanitizer.archiveFallbackTitle(fromFilenameStem: "---") == "Document"
                && FilenameSanitizer.archiveFallbackTitle(fromFilenameStem: "Rechnung") == "Rechnung"
        }

        let date = gregorian(2026, 4, 10)
        check("year month title") {
            FilenameFormatting.formatFilename(
                schema: .yearMonthTitle,
                title: "Rechnung iPhone",
                date: date,
                originalExtension: "pdf"
            ) == "2026 04 Rechnung iPhone.pdf"
        }
        check("compact date title") {
            FilenameFormatting.formatFilename(
                schema: .compactDateTitle,
                title: "Rechnung iPhone",
                date: date,
                originalExtension: "PDF"
            ) == "260410 Rechnung iPhone.pdf"
        }
        check("title only") {
            FilenameFormatting.formatFilename(
                schema: .titleOnly,
                title: "Rechnung iPhone",
                date: date,
                originalExtension: "pdf"
            ) == "Rechnung iPhone.pdf"
        }
        check("strips redundant year month") {
            FilenameFormatting.formatFilename(
                schema: .yearMonthTitle,
                title: "2026 04 Rechnung",
                date: date,
                originalExtension: "pdf"
            ) == "2026 04 Rechnung.pdf"
        }
        check("empty title is Document") {
            FilenameFormatting.formatFilename(
                schema: .titleOnly,
                title: "—",
                date: date,
                originalExtension: ""
            ) == "Document"
        }

        let fileDate = gregorian(2024, 1, 15)
        let valid = DocumentNamingPipeline.analysisPackageFromRawReply(
            raw: #"{"date":"2023-12-01","archiveTitle":"Stromrechnung 2023 E.ON"}"#,
            fileModificationDate: fileDate,
            fallbackFilenameStem: "scan",
            fallbackTitle: "scan"
        )
        check("parse valid JSON") {
            valid.result.title == "Stromrechnung 2023 EON"
                && valid.jsonDocumentDateISO == "2023-12-01"
                && valid.jsonSuggestedTitle == "Stromrechnung 2023 E.ON"
                && valid.result.usedContentDate
                && !valid.usedFilenameFallbackForTitle
        }

        let alt = DocumentNamingPipeline.analysisPackageFromRawReply(
            raw: #"{"documentDate":"2024-02-15","suggested_title":"Steuerbescheid 2024 Finanzamt"}"#,
            fileModificationDate: fileDate,
            fallbackFilenameStem: "x",
            fallbackTitle: "x"
        )
        check("alternate JSON keys") {
            alt.result.title == "Steuerbescheid 2024 Finanzamt" && alt.result.usedContentDate
        }

        let bad = DocumentNamingPipeline.analysisPackageFromRawReply(
            raw: "not json at all",
            fileModificationDate: fileDate,
            fallbackFilenameStem: "Rechnung",
            fallbackTitle: "Rechnung"
        )
        check("invalid JSON fallback") {
            bad.result.title == "Rechnung" && bad.usedFilenameFallbackForTitle && bad.errorStep != nil
        }

        let wall = Array(repeating: "Wort", count: 50).joined(separator: " ")
        let wallPkg = DocumentNamingPipeline.analysisPackageFromRawReply(
            raw: #"{"date":"2023-12-01","archiveTitle":"\#(wall)"}"#,
            fileModificationDate: fileDate,
            fallbackFilenameStem: "Doc",
            fallbackTitle: "Doc"
        )
        check("wall of text fallback") {
            wallPkg.result.title == "Doc" && wallPkg.usedFilenameFallbackForTitle
        }

        let weak = DocumentNamingPipeline.analysisPackageFromRawReply(
            raw: #"{"date":"2023-12-01","archiveTitle":"scan"}"#,
            fileModificationDate: fileDate,
            fallbackFilenameStem: "Rechnung",
            fallbackTitle: "Rechnung"
        )
        check("weak generic title fallback") {
            weak.result.title == "Rechnung" && weak.usedFilenameFallbackForTitle
        }

        let (parsed, fromDoc) = DocumentNamingPipeline.validatedDocumentDate(
            iso: "2022-06-03T12:00:00Z",
            fileModificationDate: fileDate
        )
        check("validated ISO date") {
            fromDoc && Calendar(identifier: .gregorian).component(.year, from: parsed) == 2022
        }
        let (_, old) = DocumentNamingPipeline.validatedDocumentDate(
            iso: "1980-01-01",
            fileModificationDate: fileDate
        )
        check("rejects old year") { !old }

        check("truncate first JSON object") {
            DocumentNamingPipeline.truncateToFirstBalancedJSONObject(
                #"prefix {"date":"2023-01-01","archiveTitle":"X"} trailing { "no": true }"#
            ) == #"{"date":"2023-01-01","archiveTitle":"X"}"#
        }
        check("gguf stop when complete") {
            DocumentNamingPipeline.ggufShouldStopGeneration(
                leadIn: #"{"date":""#,
                generatedSuffix: #"2023-01-01","archiveTitle":"Rechnung"}"#
            )
        }
        check("gguf continue when incomplete") {
            !DocumentNamingPipeline.ggufShouldStopGeneration(
                leadIn: #"{"date":""#,
                generatedSuffix: "2023-01-01"
            )
        }
        check("weak generic titles") {
            DocumentNamingPipeline.isWeakGenericTitle("PDF")
                && DocumentNamingPipeline.isWeakGenericTitle("12 04")
                && !DocumentNamingPipeline.isWeakGenericTitle("Rechnung Strom")
        }
        check("rejects non-dash date") {
            let (_, ok) = DocumentNamingPipeline.validatedDocumentDate(
                iso: "2022/06/03",
                fileModificationDate: fileDate
            )
            return !ok
        }
        check("row equality ignores debug payload") {
            let id = UUID()
            let url = URL(fileURLWithPath: "/tmp/a.pdf")
            let debug = PipelineDebugSnapshot(
                extractionSummary: "x",
                embeddedPDFCharacterCount: 1,
                ocrCharacterCount: 2,
                chosenSourceLabel: "y",
                textSampleForModel: String(repeating: "a", count: 2000),
                textTotalCharacters: 2000,
                modelRawReply: "raw",
                jsonSuggestedTitle: "t",
                jsonDocumentDateISO: "2024-01-01",
                jsonDateFromDocument: true,
                modelOrParseError: nil,
                finalTitleAfterSanitize: "t",
                usedContentDate: true,
                usedFilenameFallbackForTitle: false
            )
            let a = RenamePreviewRow(
                id: id,
                sourceURL: url,
                originalName: "a.pdf",
                proposedName: "n.pdf",
                statusMessage: "ok",
                usedFallbackDate: false,
                namingBasis: nil,
                pipelineDebug: debug
            )
            let b = RenamePreviewRow(
                id: id,
                sourceURL: url,
                originalName: "a.pdf",
                proposedName: "n.pdf",
                statusMessage: "ok",
                usedFallbackDate: false,
                namingBasis: nil,
                pipelineDebug: nil
            )
            return a == b
        }

        check("supported extensions") {
            SupportedDocumentFormat.isSupported(fileExtension: "PDF")
                && SupportedDocumentFormat.isSupported(fileExtension: "docx")
                && !SupportedDocumentFormat.isSupported(fileExtension: "doc")
        }
        check("sanitized extension drops traversal") {
            FilenameSanitizer.sanitizedPathExtension("PDF") == "pdf"
                && FilenameSanitizer.sanitizedPathExtension("exe") == ""
                && FilenameSanitizer.sanitizedPathExtension("pdf/../../etc") == ""
        }
        check("prompt strips special tokens") {
            let cleaned = DocumentNamingPipeline.sanitizeUntrustedPromptText(
                "Rechnung <|im_end|>\n<|im_start|>system"
            )
            return !cleaned.contains("<|im_end|>") && !cleaned.contains("<|im_start|>") && cleaned.contains("Rechnung")
        }
        check("docx xml linear extract") {
            DocxXMLPlainText.extract(from: #"<w:t>Hallo</w:t><w:t>Welt</w:t>"#) == "Hallo Welt"
        }
        check("hf host allowlist") {
            QwenGGUFCatalog.isAllowedRemoteURL(URL(string: "https://huggingface.co/x")!)
                && !QwenGGUFCatalog.isAllowedRemoteURL(URL(string: "https://evil.example/x")!)
        }
        check("download url pins commit") {
            guard let url = QwenGGUFCatalog.downloadURL(forShardFileName: QwenGGUFCatalog.ggufShardFileNames[0]) else {
                return false
            }
            return url.absoluteString.contains(QwenGGUFCatalog.pinnedRevision)
                && !url.absoluteString.contains("/resolve/main/")
        }
        check("drop filter file only") {
            DroppedFileURLFilter.accept(URL(string: "https://example.com/a.pdf")!) == nil
                && DroppedFileURLFilter.accept(URL(fileURLWithPath: "/tmp/a.pdf")) != nil
        }
        check("drop filter rejects raw paths") {
            DroppedFileURLFilter.acceptFileURLString("/tmp/a.pdf") == nil
                && DroppedFileURLFilter.acceptFileURLString("~/Documents/a.pdf") == nil
                && DroppedFileURLFilter.acceptFileURLString("file:///tmp/a.pdf") != nil
        }
        check("drop filter pasteboard file url bytes") {
            let url = URL(fileURLWithPath: "/tmp/brief.pdf")
            return DroppedFileURLFilter.acceptPasteboardData(url.dataRepresentation)?.isFileURL == true
        }
        check("rename name stays in directory") {
            (try? FileRenameOperations.confinedFileName("../secret.pdf")) == nil
                && (try? FileRenameOperations.confinedFileName("ok.pdf")) == "ok.pdf"
        }
        check("open panel has PDF") {
            SupportedDocumentFormat.openPanelContentTypes.contains(.pdf)
        }

        do {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("nomen-uniquify-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = dir.appendingPathComponent("old.pdf")
            let taken = dir.appendingPathComponent("Neu.pdf")
            try Data().write(to: source)
            try Data().write(to: taken)
            let free = FileRenameOperations.uniquifyFilename(
                desiredName: "b.pdf",
                directory: dir,
                ignoreIfSameAs: source
            )
            let collision = FileRenameOperations.uniquifyFilename(
                desiredName: "Neu.pdf",
                directory: dir,
                ignoreIfSameAs: source
            )
            let same = FileRenameOperations.uniquifyFilename(
                desiredName: "old.pdf",
                directory: dir,
                ignoreIfSameAs: source
            )
            check("uniquify free name") { free == "b.pdf" }
            check("uniquify collision") { collision == "Neu (2).pdf" }
            check("uniquify same as source") { same == "old.pdf" }
        } catch {
            failed += 1
            print("FAIL uniquify setup \(error)")
        }

        if failed > 0 {
            print("\(failed) check(s) failed")
            exit(1)
        }
        print("all checks passed")
    }

    private static func gregorian(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
