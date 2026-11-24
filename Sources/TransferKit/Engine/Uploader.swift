import Foundation

/// Drives a single upload to completion: initiate (or resume) → upload the
/// pending parts with bounded parallelism and per-part retry → checkpoint each
/// confirmed part → complete. Interruptible and resumable at any point.
public actor Uploader {
    private let store: TransferStore
    private let s3: S3Client
    private let config: UploaderConfig

    public init(store: TransferStore, s3: S3Client, config: UploaderConfig = .default) {
        self.store = store
        self.s3 = s3
        self.config = config
    }

    /// Start or resume `job`, reading part bytes from `source`.
    /// `onProgress` is called after each confirmed part with (completed, total).
    public func run(
        _ job: TransferJob,
        source: PartDataSource,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        var job = try await prepared(job)
        guard let uploadID = job.uploadID else { throw UploaderError.notStarted }

        let pending = job.parts.filter { $0.state != .uploaded }
        job = try await uploadPending(
            pending, in: job, uploadID: uploadID, source: source, onProgress: onProgress)

        guard job.parts.allSatisfy({ $0.state == .uploaded && $0.eTag != nil }) else {
            throw UploaderError.incompleteUpload
        }

        let uploaded = job.parts
            .compactMap { part in part.eTag.map { UploadedPart(number: part.number, eTag: $0) } }
            .sorted { $0.number < $1.number }

        try await s3.completeMultipartUpload(
            bucket: job.bucket, key: job.key, uploadID: uploadID, parts: uploaded)
        job.state = .completed
        try await save(&job)
    }

    /// Abort the multipart upload on S3 and mark the job aborted.
    public func abort(_ job: TransferJob) async throws {
        guard let uploadID = job.uploadID else { return }
        try await s3.abortMultipartUpload(bucket: job.bucket, key: job.key, uploadID: uploadID)
        var job = job
        job.state = .aborted
        try await save(&job)
    }

    // MARK: - Private

    /// Ensure the job has an upload id and a part plan; on resume, reconcile the
    /// part states against what S3 already holds (via `listParts`).
    private func prepared(_ job: TransferJob) async throws -> TransferJob {
        var job = job
        job.state = .uploading

        if job.uploadID == nil {
            job.uploadID = try await s3.createMultipartUpload(bucket: job.bucket, key: job.key)
            if job.parts.isEmpty {
                job.parts = PartPlanner.plan(totalSize: job.totalSize, partSize: config.partSize)
            }
        } else if let uploadID = job.uploadID {
            let existing = try await s3.listParts(bucket: job.bucket, key: job.key, uploadID: uploadID)
            let eTagByNumber = Dictionary(
                existing.map { ($0.number, $0.eTag) }, uniquingKeysWith: { a, _ in a })
            job.parts = job.parts.map { part in
                var part = part
                if let eTag = eTagByNumber[part.number] {
                    part.state = .uploaded
                    part.eTag = eTag
                }
                return part
            }
        }

        try await save(&job)
        return job
    }

    /// Upload the pending parts, at most `maxConcurrentParts` at a time, checkpointing
    /// each confirmed part to the store so a crash can resume from here.
    private func uploadPending(
        _ pending: [TransferPart],
        in job: TransferJob,
        uploadID: String,
        source: PartDataSource,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> TransferJob {
        guard !pending.isEmpty else { return job }

        var job = job
        let s3 = self.s3
        let bucket = job.bucket
        let key = job.key
        let maxRetries = config.maxRetries
        let baseSeconds = config.retryBaseSeconds
        let maxConcurrent = max(1, config.maxConcurrentParts)

        let uploadOne: @Sendable (TransferPart) async throws -> PartResult = { part in
            let data = try await source.read(offset: part.offset, size: part.size)
            let eTag = try await Retry.run(maxAttempts: maxRetries, baseSeconds: baseSeconds) {
                try await s3.uploadPart(
                    bucket: bucket, key: key, uploadID: uploadID,
                    partNumber: part.number, data: data)
            }
            return PartResult(number: part.number, eTag: eTag)
        }

        try await withThrowingTaskGroup(of: PartResult.self) { group in
            var iterator = pending.makeIterator()
            var inFlight = 0

            for _ in 0..<maxConcurrent {
                guard let part = iterator.next() else { break }
                group.addTask { try await uploadOne(part) }
                inFlight += 1
            }

            while inFlight > 0 {
                guard let result = try await group.next() else { break }
                inFlight -= 1

                if let index = job.parts.firstIndex(where: { $0.number == result.number }) {
                    job.parts[index].state = .uploaded
                    job.parts[index].eTag = result.eTag
                }
                try await save(&job)  // checkpoint
                let done = job.parts.filter { $0.state == .uploaded }.count
                onProgress?(done, job.parts.count)

                // Stop queuing new parts once cancelled (paused); let the
                // already-in-flight parts finish and checkpoint.
                if !Task.isCancelled, let part = iterator.next() {
                    group.addTask { try await uploadOne(part) }
                    inFlight += 1
                }
            }
        }

        // Surface the pause/cancel after in-flight parts have drained + saved.
        try Task.checkCancellation()
        return job
    }

    /// Stamp `updatedAt` and persist.
    private func save(_ job: inout TransferJob) async throws {
        job.updatedAt = Date()
        try await store.upsert(job)
    }

    private struct PartResult: Sendable {
        let number: Int
        let eTag: String
    }
}

public enum UploaderError: Error, Sendable {
    case notStarted  // no upload id after prepare (shouldn't happen)
    case incompleteUpload  // a part didn't finish; job left resumable
}
