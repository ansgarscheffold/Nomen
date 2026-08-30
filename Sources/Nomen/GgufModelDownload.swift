import Foundation
import NomenCore

enum GgufModelDownloadError: LocalizedError {
    case badHTTPStatus(Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badHTTPStatus(let code):
            return "Server antwortete mit HTTP \(code)."
        case .cancelled:
            return "Download wurde abgebrochen."
        }
    }
}

/// GGUF-Download über eine Background-`URLSession` mit Resume-Daten auf Disk.
enum GgufModelDownload {
    /// `fraction` ist 0…1 wenn die Gesamtgröße bekannt ist, sonst `nil`.
    @MainActor
    static func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (Double?) -> Void
    ) async throws {
        try await GgufDownloadCoordinator.shared.download(
            from: remoteURL,
            to: destinationURL,
            onProgress: onProgress
        )
    }
}

final class GgufDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = GgufDownloadCoordinator()

    private struct Pending {
        let destinationURL: URL
        let resumeURL: URL
        let remoteURL: URL
        let onProgress: (Double?) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        var retriedWithoutResume = false
    }

    private var pending: [Int: Pending] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "app.nomen.gguf-download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    @MainActor
    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (Double?) -> Void
    ) async throws {
        let resumeURL = Self.resumeFileURL(for: destinationURL)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            startTask(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                resumeURL: resumeURL,
                onProgress: onProgress,
                continuation: continuation,
                allowResume: true
            )
        }
    }

    private static func resumeFileURL(for destinationURL: URL) -> URL {
        destinationURL.appendingPathExtension("nomenresume")
    }

    private func startTask(
        remoteURL: URL,
        destinationURL: URL,
        resumeURL: URL,
        onProgress: @escaping (Double?) -> Void,
        continuation: CheckedContinuation<Void, Error>,
        allowResume: Bool
    ) {
        let task: URLSessionDownloadTask
        if allowResume, let data = try? Data(contentsOf: resumeURL), !data.isEmpty {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: remoteURL)
        }
        pending[task.taskIdentifier] = Pending(
            destinationURL: destinationURL,
            resumeURL: resumeURL,
            remoteURL: remoteURL,
            onProgress: onProgress,
            continuation: continuation,
            retriedWithoutResume: !allowResume
        )
        task.resume()
    }

    private func finish(taskId: Int, _ result: Result<Void, Error>) {
        guard var item = pending.removeValue(forKey: taskId) else { return }
        switch result {
        case .success:
            try? FileManager.default.removeItem(at: item.resumeURL)
            item.continuation?.resume()
        case .failure(let error):
            item.continuation?.resume(throwing: error)
        }
        item.continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let item = pending[downloadTask.taskIdentifier] else { return }
        if totalBytesExpectedToWrite > 0 {
            item.onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        } else {
            item.onProgress(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let item = pending[downloadTask.taskIdentifier] else { return }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                throw GgufModelDownloadError.badHTTPStatus(http.statusCode)
            }
            let fm = FileManager.default
            let parent = item.destinationURL.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: item.destinationURL.path) {
                try fm.removeItem(at: item.destinationURL)
            }
            try fm.moveItem(at: location, to: item.destinationURL)
            finish(taskId: downloadTask.taskIdentifier, .success(()))
        } catch {
            finish(taskId: downloadTask.taskIdentifier, .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        guard pending[task.taskIdentifier] != nil else { return }

        let ns = error as NSError
        if let resume = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, !resume.isEmpty,
           let item = pending[task.taskIdentifier] {
            try? resume.write(to: item.resumeURL, options: .atomic)
        }

        let cancelled = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
        if cancelled {
            finish(taskId: task.taskIdentifier, .failure(GgufModelDownloadError.cancelled))
            return
        }

        if let item = pending[task.taskIdentifier], !item.retriedWithoutResume {
            try? FileManager.default.removeItem(at: item.resumeURL)
            let dest = item.destinationURL
            let resumeURL = item.resumeURL
            let remote = item.remoteURL
            let progress = item.onProgress
            let continuation = item.continuation
            pending.removeValue(forKey: task.taskIdentifier)
            if let continuation {
                startTask(
                    remoteURL: remote,
                    destinationURL: dest,
                    resumeURL: resumeURL,
                    onProgress: progress,
                    continuation: continuation,
                    allowResume: false
                )
            }
            return
        }

        finish(taskId: task.taskIdentifier, .failure(error))
    }
}
