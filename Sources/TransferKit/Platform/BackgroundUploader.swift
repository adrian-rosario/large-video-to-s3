import Foundation

/// Uploads a whole file to a presigned URL using a **background** URLSession, so
/// the system continues the transfer when the app is suspended — the native
/// Apple answer to "keep uploading after the app goes away."
///
/// NOTE: true survive-app-termination behavior requires a real `.app` bundle; a
/// bare `swift run` executable has no bundle identifier, so it degrades to an
/// in-process (foreground) transfer. Full *multipart*-over-background (per-part
/// presigned URLs + temp part files + reassembly) is a larger extension; this
/// component covers the whole-file PUT pattern.
///
/// `@unchecked Sendable`: the closures are `@Sendable`; the session is created
/// lazily and the delegate callbacks arrive on URLSession's own serial queue.
public final class BackgroundUploader: NSObject, @unchecked Sendable {
    public struct Progress: Sendable {
        public let bytesSent: Int64
        public let totalBytes: Int64
    }

    private let onProgress: @Sendable (Progress) -> Void
    private let onComplete: @Sendable (Result<Void, Error>) -> Void

    // Unique per instance: background sessions require a distinct identifier, so
    // reusing a fixed string would crash a second uploader in the same process.
    private let identifier = "com.largevideotos3.background-upload.\(UUID().uuidString)"
    private var session: URLSession?

    public init(
        onProgress: @escaping @Sendable (Progress) -> Void,
        onComplete: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    /// PUT `fileURL` to a presigned `url`. The transfer runs on a background
    /// session and reports completion/failure via the init callbacks.
    public func upload(fileURL: URL, to url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        makeSession().uploadTask(with: request, fromFile: fileURL).resume()
    }

    /// Cancel any in-flight task and release the session (breaks the delegate
    /// retain cycle). Called automatically on completion; expose it for callers
    /// that want to tear down early.
    public func invalidate() {
        session?.invalidateAndCancel()
        session = nil
    }

    private func makeSession() -> URLSession {
        if let session { return session }
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true
        let created = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = created
        return created
    }
}

extension BackgroundUploader: URLSessionTaskDelegate {
    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(Progress(bytesSent: totalBytesSent, totalBytes: totalBytesExpectedToSend))
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        // Release the session (and the delegate retain cycle) once finished.
        defer { session.finishTasksAndInvalidate() }

        if let error {
            onComplete(.failure(error))
        } else if let http = task.response as? HTTPURLResponse,
            !(200..<300).contains(http.statusCode)
        {
            // A non-transport failure (e.g. 403/404/5xx) completes with no error,
            // so inspect the status code or the upload looks falsely successful.
            onComplete(.failure(S3Error.fatal("HTTP \(http.statusCode)")))
        } else {
            onComplete(.success(()))
        }
    }
}
