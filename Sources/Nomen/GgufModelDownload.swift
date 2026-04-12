import Foundation

enum GgufModelDownloadError: LocalizedError {
    case badHTTPStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badHTTPStatus(let code):
            return "Server antwortete mit HTTP \(code)."
        }
    }
}

/// GGUF-Download mit Fortschritt (`URLSessionDownloadDelegate`). Läuft mit `delegateQueue: .main`.
enum GgufModelDownload {
    /// `fraction` ist 0…1 wenn die Gesamtgröße bekannt ist, sonst `nil` (nur Balken ohne Anteil).
    @MainActor
    static func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (Double?) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let runner = DownloadRunner(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                onProgress: onProgress,
                continuation: continuation
            )
            runner.start()
        }
    }
}

private final class DownloadRunner: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let remoteURL: URL
    private let destinationURL: URL
    private let onProgress: (Double?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession!
    private var completed = false

    init(
        remoteURL: URL,
        destinationURL: URL,
        onProgress: @escaping (Double?) -> Void,
        continuation: CheckedContinuation<Void, Error>
    ) {
        self.remoteURL = remoteURL
        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.continuation = continuation
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func start() {
        session.downloadTask(with: remoteURL).resume()
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !completed else { return }
        completed = true
        session.finishTasksAndInvalidate()
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let f = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            onProgress(f)
        } else {
            onProgress(nil)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                throw GgufModelDownloadError.badHTTPStatus(http.statusCode)
            }
            let fm = FileManager.default
            let parent = destinationURL.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }
}
