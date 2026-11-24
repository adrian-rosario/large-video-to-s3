import Foundation

/// An in-memory `S3Client` for tests and local runs. Records parts, hands back
/// stable ETags, and can inject failures so the engine's retry/resume paths are
/// provable without touching the network.
public actor FakeS3Client: S3Client {
    /// For part `N`, throw a transient error this many times before succeeding.
    /// Lets a test force retries and interrupted-then-resumed uploads.
    private var transientFailuresRemaining: [Int: Int]

    private struct Upload {
        let bucket: String
        let key: String
        var parts: [Int: (data: Data, eTag: String)] = [:]
        var completed = false
    }

    private var uploads: [String: Upload] = [:]
    private var counter = 0
    private var attempts: [Int: Int] = [:]  // uploadPart calls per part number

    public init(transientFailures: [Int: Int] = [:]) {
        self.transientFailuresRemaining = transientFailures
    }

    public func createMultipartUpload(bucket: String, key: String) async throws -> String {
        counter += 1
        let uploadID = "fake-upload-\(counter)"
        uploads[uploadID] = Upload(bucket: bucket, key: key)
        return uploadID
    }

    public func uploadPart(
        bucket: String,
        key: String,
        uploadID: String,
        partNumber: Int,
        data: Data
    ) async throws -> String {
        guard uploads[uploadID] != nil else { throw S3Error.noSuchUpload }
        attempts[partNumber, default: 0] += 1

        if let remaining = transientFailuresRemaining[partNumber], remaining > 0 {
            transientFailuresRemaining[partNumber] = remaining - 1
            throw S3Error.transient("injected failure for part \(partNumber)")
        }

        let eTag = "\"fake-etag-\(partNumber)-\(data.count)\""
        uploads[uploadID]?.parts[partNumber] = (data, eTag)
        return eTag
    }

    public func listParts(bucket: String, key: String, uploadID: String) async throws -> [UploadedPart] {
        guard let upload = uploads[uploadID] else { throw S3Error.noSuchUpload }
        return upload.parts
            .map { UploadedPart(number: $0.key, eTag: $0.value.eTag) }
            .sorted { $0.number < $1.number }
    }

    public func completeMultipartUpload(
        bucket: String,
        key: String,
        uploadID: String,
        parts: [UploadedPart]
    ) async throws {
        guard uploads[uploadID] != nil else { throw S3Error.noSuchUpload }
        uploads[uploadID]?.completed = true
    }

    public func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws {
        uploads.removeValue(forKey: uploadID)
    }

    // MARK: - Test introspection

    /// Number of distinct parts S3 currently holds for an upload.
    public func storedPartCount(uploadID: String) -> Int {
        uploads[uploadID]?.parts.count ?? 0
    }

    /// Whether an upload was completed.
    public func isCompleted(uploadID: String) -> Bool {
        uploads[uploadID]?.completed ?? false
    }

    /// Total `uploadPart` calls seen for a part number (incl. failed attempts).
    public func attemptCount(part: Int) -> Int {
        attempts[part] ?? 0
    }

    /// Clear injected failures — simulates the transient condition clearing
    /// between a failed run and a successful resume.
    public func clearTransientFailures() {
        transientFailuresRemaining.removeAll()
    }
}
