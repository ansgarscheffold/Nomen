import Foundation
import UniformTypeIdentifiers

/// Unterstützte Eingabeformate — eine Liste für Filter, Open-Panel und Extraktion.
public enum SupportedDocumentFormat: String, CaseIterable, Sendable {
    case pdf
    case txt
    case md
    case markdown
    case csv
    case log
    case rtf
    case rtfd
    case docx

    public static func isSupported(url: URL) -> Bool {
        isSupported(fileExtension: url.pathExtension)
    }

    public static func isSupported(fileExtension: String) -> Bool {
        Self(rawValue: fileExtension.lowercased()) != nil
    }

    public static var openPanelContentTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf, .text]
        if let md = UTType(filenameExtension: md.rawValue) { types.append(md) }
        if let markdown = UTType(filenameExtension: markdown.rawValue) { types.append(markdown) }
        if let docx = UTType(filenameExtension: docx.rawValue) { types.append(docx) }
        return types
    }
}
