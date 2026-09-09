import Foundation

/// One file, to one place, reporting bytes as they land.
///
/// `URLSession.bytes` would be shorter, but it yields one `UInt8` at a time: a 150 MB model is
/// 150 million loop iterations and minutes of CPU spent doing nothing. A download task with a
/// delegate streams straight to disk and just tells us how far it has got.
enum FileDownload {
    /// Downloads `url` to `destination`, calling `onProgress` with the running byte count.
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
        /// Set once, before the task starts; read once, when it ends.
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

        /// The temporary file is gone as soon as this returns, so the move has to happen here.
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

        /// A failed download reports through both callbacks; the continuation may only be used once.
        private func resume(with result: Result<URL, Error>) {
            guard !finished else { return }
            finished = true
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}
