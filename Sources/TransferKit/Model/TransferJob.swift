import Foundation

/// A single file's upload to S3, including everything needed to resume it.
///
/// This is the unit the `TransferStore` persists. Keep it a plain value type so
/// it is trivially `Sendable` and easy to snapshot, diff, and test.
public struct TransferJob: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let fileURL: URL        // source file (resolved via a security-scoped bookmark later)
    public let bucket: String
    public let key: String         // destination object key
    public let totalSize: Int64

    public var uploadID: String?   // S3 multipart UploadId, set after initiate
    public var state: TransferState
    public var parts: [TransferPart]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        bucket: String,
        key: String,
        totalSize: Int64,
        uploadID: String? = nil,
        state: TransferState = .pending,
        parts: [TransferPart] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.bucket = bucket
        self.key = key
        self.totalSize = totalSize
        self.uploadID = uploadID
        self.state = state
        self.parts = parts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Bytes confirmed uploaded so far (sum of completed parts).
    public var bytesUploaded: Int64 {
        parts.filter { $0.state == .uploaded }.reduce(0) { $0 + $1.size }
    }

    /// Fraction complete in 0...1, guarding against an empty/zero-size job.
    public var progress: Double {
        guard totalSize > 0 else { return 0 }
        return Double(bytesUploaded) / Double(totalSize)
    }

    /// Parts still needing upload — the work a resumed run must re-drive.
    public var pendingParts: [TransferPart] {
        parts.filter { $0.state != .uploaded }
    }
}
