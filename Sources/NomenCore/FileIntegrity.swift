import CryptoKit
import Foundation

public enum FileIntegrityError: LocalizedError {
    case sizeMismatch(expected: Int64, actual: Int64)
    case hashMismatch
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .sizeMismatch:
            return "Die Dateigröße stimmt nicht mit der erwarteten Modelldatei überein."
        case .hashMismatch:
            return "Die Prüfsumme der Modelldatei ist ungültig."
        case .unreadable:
            return "Die Datei konnte nicht zur Integritätsprüfung gelesen werden."
        }
    }
}

public enum FileIntegrity {
    private static let chunkBytes = 1_048_576

    public static func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else { throw FileIntegrityError.unreadable }
        return Int64(size)
    }

    public static func sha256Hex(ofFile url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw FileIntegrityError.unreadable
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkBytes) ?? Data()
            } catch {
                throw FileIntegrityError.unreadable
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(
        url: URL,
        expectedSHA256Hex: String,
        expectedByteCount: Int64
    ) throws {
        let size = try fileSize(at: url)
        guard size == expectedByteCount else {
            throw FileIntegrityError.sizeMismatch(expected: expectedByteCount, actual: size)
        }
        let digest = try sha256Hex(ofFile: url)
        guard digest.lowercased() == expectedSHA256Hex.lowercased() else {
            throw FileIntegrityError.hashMismatch
        }
    }
}
