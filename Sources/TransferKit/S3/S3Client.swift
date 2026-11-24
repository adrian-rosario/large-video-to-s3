import Foundation

/// A part that S3 has confirmed it holds (number + ETag), used both when
/// completing an upload and when reconciling a resumed one via `listParts`.
public struct UploadedPart: Sendable, Equatable {
    public let number: Int
    public let eTag: String

    public init(number: Int, eTag: String) {
        self.number = number
        self.eTag = eTag
    }
}

/// The slice of the S3 multipart API the engine needs. Kept deliberately small
/// so the real (AWS SDK) and fake implementations are easy to reason about.
public protocol S3Client: Sendable {
    /// Begin a multipart upload; returns the S3 UploadId.
    func createMultipartUpload(bucket: String, key: String) async throws -> String

    /// Upload one part; returns its ETag. Safe to retry for the same part number.
    func uploadPart(
        bucket: String,
        key: String,
        uploadID: String,
        partNumber: Int,
        data: Data
    ) async throws -> String

    /// List the parts S3 already holds — the source of truth when resuming.
    func listParts(bucket: String, key: String, uploadID: String) async throws -> [UploadedPart]

    /// Assemble the object from its parts.
    func completeMultipartUpload(
        bucket: String,
        key: String,
        uploadID: String,
        parts: [UploadedPart]
    ) async throws

    /// Abort the upload and discard any stored parts (avoids orphaned-part cost).
    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws
}

/// Errors surfaced by an `S3Client`.
public enum S3Error: Error, Equatable, Sendable {
    case noSuchUpload
    case transient(String)   // retryable (timeout, 5xx, throttle)
    case fatal(String)       // not retryable (auth, bad request)

    /// Whether the engine should retry after this error.
    public var isRetryable: Bool {
        switch self {
        case .transient: true
        case .noSuchUpload, .fatal: false
        }
    }
}
