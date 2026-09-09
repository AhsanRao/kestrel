import Foundation

/// One file, to one place, reporting bytes as they land.
///
/// Not `URLSession.bytes`: it yields a byte at a time, so a 350 MB model is 350 million loop
/// iterations. A download task streams to disk and just reports progress.
enum FileDownload {
    /// Calls `onProgress` with the running byte count.
    static func fetch(_ url: URL,
                      to destination: URL,
                      onProgress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let delegate = Delegate(destination: destination, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let onProgress: @Sendable (Int64) -> Void
        /// Set before the task starts, read when it ends.
        var continuation: CheckedContinuation<URL, Error>?
        private var finished = false

        init(destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            onProgress(totalBytesWritten)
        }

        /// The temp file is gone once this returns, so move it here.
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                return resume(with: .failure(KestrelError.speech(
                    "The download failed with HTTP \(code) — try again later.")))
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                resume(with: .success(destination))
            } catch {
                resume(with: .failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            resume(with: .failure(error))
        }

        /// A failure reports through both callbacks; the continuation is single-use.
        private func resume(with result: Result<URL, Error>) {
            guard !finished else { return }
            finished = true
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}
