import Foundation

/// Qwen2.5-7B-Instruct (GGUF, Q4_K_M, zwei Shards) — Hugging Face `Qwen/Qwen2.5-7B-Instruct-GGUF`.
/// llama.cpp lädt über das erste Shard; das zweite muss im selben Ordner liegen.
enum QwenGGUFModelSupport {
    private static let huggingFaceResolveBase =
        "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main"

    static let ggufShardFileNames = [
        "qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf",
        "qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf",
    ]

    /// Gesamtgröße beider Shards (ungefähr).
    static let approximateDownloadMegabytes = 4500

    static func downloadURL(forShardFileName fileName: String) -> URL {
        URL(string: "\(huggingFaceResolveBase)/\(fileName)")!
    }

    static var modelsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
        ggufShardFileNames.allSatisfy {
            FileManager.default.fileExists(atPath: localURL(forShardFileName: $0).path)
        }
    }

    /// Alle Shard-Pfade (Finder-Auswahl), wenn `isDownloaded`.
    static var allLocalShardURLs: [URL] {
        ggufShardFileNames.map { localURL(forShardFileName: $0) }
    }
}
