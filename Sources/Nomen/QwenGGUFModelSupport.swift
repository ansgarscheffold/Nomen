import Foundation
import NomenCore

/// Qwen2.5-7B-Instruct (GGUF, Q4_K_M, zwei Shards) — Hugging Face `Qwen/Qwen2.5-7B-Instruct-GGUF`.
/// llama.cpp lädt über das erste Shard; das zweite muss im selben Ordner liegen.
enum QwenGGUFModelSupport {
    static let ggufShardFileNames = QwenGGUFCatalog.ggufShardFileNames

    /// Gesamtgröße beider Shards (ungefähr, MB).
    static let approximateDownloadMegabytes = QwenGGUFCatalog.approximateDownloadMegabytes

    private static let verifyLock = NSLock()
    nonisolated(unsafe) private static var integrityVerifiedThisProcess = false

    static var modelsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Nomen", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Erstes Shard — Pfad für `llama_model_load_from_file`.
    static var localFileURL: URL {
        modelsDirectoryURL.appendingPathComponent(ggufShardFileNames[0], isDirectory: false)
    }

    static func localURL(forShardFileName fileName: String) -> URL {
        modelsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    static func ensureModelsDirectoryExists() throws {
        try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    static var isDownloaded: Bool {
        QwenGGUFCatalog.shards.allSatisfy { shard in
            let url = localURL(forShardFileName: shard.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            return (try? FileIntegrity.fileSize(at: url)) == shard.byteCount
        }
    }

    static func resetIntegrityCache() {
        verifyLock.lock()
        integrityVerifiedThisProcess = false
        verifyLock.unlock()
    }

    /// SHA-256 beider Shards. Nach Erfolg im Prozess gecacht (4+ GB).
    static func verifyAllShardsOnDisk() throws {
        verifyLock.lock()
        let alreadyVerified = integrityVerifiedThisProcess
        verifyLock.unlock()
        if alreadyVerified { return }

        for shard in QwenGGUFCatalog.shards {
            let url = localURL(forShardFileName: shard.fileName)
            do {
                try FileIntegrity.verify(
                    url: url,
                    expectedSHA256Hex: shard.sha256Hex,
                    expectedByteCount: shard.byteCount
                )
            } catch {
                try? FileManager.default.removeItem(at: url)
                verifyLock.lock()
                integrityVerifiedThisProcess = false
                verifyLock.unlock()
                throw error
            }
        }
        verifyLock.lock()
        integrityVerifiedThisProcess = true
        verifyLock.unlock()
    }

    /// Alle Shard-Pfade (Finder-Auswahl), wenn `isDownloaded`.
    static var allLocalShardURLs: [URL] {
        ggufShardFileNames.map { localURL(forShardFileName: $0) }
    }
}
