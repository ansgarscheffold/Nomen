import Foundation

/// Fest verdrahtete Qwen2.5-7B-Instruct Q4_K_M-Shards (Hugging Face LFS-SHA-256, Commit-Pin).
public enum QwenGGUFCatalog {
    public static let huggingFaceRepo = "Qwen/Qwen2.5-7B-Instruct-GGUF"
    /// Git-Commit statt `main`, damit der Resolve-Pfad nicht mitwandert.
    public static let pinnedRevision = "bb5d59e06d9551d752d08b292a50eb208b07ab1f"

    public struct Shard: Sendable, Equatable {
        public let fileName: String
        public let sha256Hex: String
        public let byteCount: Int64

        public init(fileName: String, sha256Hex: String, byteCount: Int64) {
            self.fileName = fileName
            self.sha256Hex = sha256Hex
            self.byteCount = byteCount
        }
    }

    public static let shards: [Shard] = [
        Shard(
            fileName: "qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf",
            sha256Hex: "dfce12e3862a5283ccfb88221b48480e58745165de856439950d0f22590580db",
            byteCount: 3_993_201_344
        ),
        Shard(
            fileName: "qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf",
            sha256Hex: "539cf93f78e887edea1c04e2d7d8cdaca9d01dae9c9025bcb8accbe29df3d72a",
            byteCount: 689_872_288
        ),
    ]

    public static var ggufShardFileNames: [String] {
        shards.map(\.fileName)
    }

    public static var approximateDownloadMegabytes: Int {
        let bytes = shards.reduce(Int64(0)) { $0 + $1.byteCount }
        return Int((bytes + 500_000) / 1_000_000)
    }

    public static func shard(named fileName: String) -> Shard? {
        shards.first { $0.fileName == fileName }
    }

    public static func downloadURL(forShardFileName fileName: String) -> URL? {
        guard shard(named: fileName) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(huggingFaceRepo)/resolve/\(pinnedRevision)/\(fileName)"
        return components.url
    }

    /// HTTPS nur zu Hugging Face / HF-CDN (inkl. Xet).
    public static func isAllowedRemoteURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return host == "huggingface.co"
            || host.hasSuffix(".huggingface.co")
            || host == "hf.co"
            || host.hasSuffix(".hf.co")
    }
}
