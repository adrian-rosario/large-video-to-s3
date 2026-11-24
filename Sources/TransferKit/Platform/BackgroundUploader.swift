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
/// `@unchecked Sendable`: the closures are `@Sendable` and the session is created
/// once; the delegate callbacks arrive on URLSession's own serial queue.
public final class BackgroundUploader: NSObject, @unchecked Sendable {
    public struct Progress: Sendable {
        public let bytesSent: Int64
        public let totalBytes: Int64
    }

    private let onProgress: @Sendable (Progress) -> Void
    private let onComplete: @Sendable (Result<Void, Error>) -> Void

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.largevideotos3.background-upload")
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public init(
        onProgress: @escaping @Sendable (Progress) -> Void,
        onComplete: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    /// PUT `fileURL` to a presigned `url`. Resumes via the background session.
    public func upload(fileURL: URL, to url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        session.uploadTask(with: request, fromFile: fileURL).resume()
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
        onComplete(error.map { .failure($0) } ?? .success(()))
    }
}
