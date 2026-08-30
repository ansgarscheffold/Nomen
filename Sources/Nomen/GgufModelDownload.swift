import Foundation
import NomenCore

enum GgufModelDownloadError: LocalizedError {
    case badHTTPStatus(Int)
    case cancelled
    case disallowedHost
    case tooLarge
    case integrityMismatch

    var errorDescription: String? {
        switch self {
        case .badHTTPStatus(let code):
            return "Server antwortete mit HTTP \(code)."
        case .cancelled:
            return "Download wurde abgebrochen."
        case .disallowedHost:
            return "Download von einem nicht erlaubten Host wurde blockiert."
        case .tooLarge:
            return "Die Datei ist größer als die erwartete Modellgröße."
        case .integrityMismatch:
            return "Die heruntergeladene Datei hat eine ungültige Prüfsumme."
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
        expectedByteCount: Int64,
        expectedSHA256Hex: String,
        onProgress: @escaping (Double?) -> Void
    ) async throws {
        try await GgufDownloadCoordinator.shared.download(
            from: remoteURL,
            to: destinationURL,
            expectedByteCount: expectedByteCount,
            expectedSHA256Hex: expectedSHA256Hex,
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
        let expectedByteCount: Int64
        let expectedSHA256Hex: String
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
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    @MainActor
    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        expectedByteCount: Int64,
        expectedSHA256Hex: String,
        onProgress: @escaping (Double?) -> Void
    ) async throws {
        guard QwenGGUFCatalog.isAllowedRemoteURL(remoteURL) else {
            throw GgufModelDownloadError.disallowedHost
        }
        let resumeURL = Self.resumeFileURL(for: destinationURL)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            startTask(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                resumeURL: resumeURL,
                expectedByteCount: expectedByteCount,
                expectedSHA256Hex: expectedSHA256Hex,
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
        expectedByteCount: Int64,
        expectedSHA256Hex: String,
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
            expectedByteCount: expectedByteCount,
            expectedSHA256Hex: expectedSHA256Hex,
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
        if totalBytesWritten > item.expectedByteCount
            || (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite > item.expectedByteCount) {
            finish(taskId: downloadTask.taskIdentifier, .failure(GgufModelDownloadError.tooLarge))
            downloadTask.cancel()
            return
        }
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
            if let finalURL = downloadTask.currentRequest?.url ?? downloadTask.originalRequest?.url,
               !QwenGGUFCatalog.isAllowedRemoteURL(finalURL) {
                throw GgufModelDownloadError.disallowedHost
            }
            let tmpSize = try FileIntegrity.fileSize(at: location)
            if tmpSize > item.expectedByteCount {
                throw GgufModelDownloadError.tooLarge
            }
            let fm = FileManager.default
            let parent = item.destinationURL.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: item.destinationURL.path) {
                try fm.removeItem(at: item.destinationURL)
            }
            try fm.moveItem(at: location, to: item.destinationURL)
            let dest = item.destinationURL
            let expectedHash = item.expectedSHA256Hex
            let expectedBytes = item.expectedByteCount
            let taskId = downloadTask.taskIdentifier
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try FileIntegrity.verify(
                        url: dest,
                        expectedSHA256Hex: expectedHash,
                        expectedByteCount: expectedBytes
                    )
                    DispatchQueue.main.async {
                        self?.finish(taskId: taskId, .success(()))
                    }
                } catch {
                    try? FileManager.default.removeItem(at: dest)
                    DispatchQueue.main.async {
                        self?.finish(taskId: taskId, .failure(GgufModelDownloadError.integrityMismatch))
                    }
                }
            }
        } catch is FileIntegrityError {
            finish(taskId: downloadTask.taskIdentifier, .failure(GgufModelDownloadError.integrityMismatch))
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
            let expectedBytes = item.expectedByteCount
            let expectedHash = item.expectedSHA256Hex
            let progress = item.onProgress
            let continuation = item.continuation
            pending.removeValue(forKey: task.taskIdentifier)
            if let continuation {
                startTask(
                    remoteURL: remote,
                    destinationURL: dest,
                    resumeURL: resumeURL,
                    expectedByteCount: expectedBytes,
                    expectedSHA256Hex: expectedHash,
                    onProgress: progress,
                    continuation: continuation,
                    allowResume: false
                )
            }
            return
        }

        finish(taskId: task.taskIdentifier, .failure(error))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, QwenGGUFCatalog.isAllowedRemoteURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
