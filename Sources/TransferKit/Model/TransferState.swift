import Foundation

/// Lifecycle state of a whole upload job.
public enum TransferState: String, Codable, Sendable {
    case pending  // created, not yet started
    case uploading  // parts are being sent
    case paused  // intentionally halted (e.g. drive disconnected); resumable
    case completed  // all parts uploaded and the object assembled
    case failed  // gave up after exhausting retries
    case aborted  // multipart upload was aborted on S3
}

/// Lifecycle state of a single part within a job.
public enum PartState: String, Codable, Sendable {
    case pending  // not yet uploaded
    case uploading  // in flight
    case uploaded  // confirmed by S3 (we hold its ETag)
    case failed  // last attempt failed; eligible for retry
}
