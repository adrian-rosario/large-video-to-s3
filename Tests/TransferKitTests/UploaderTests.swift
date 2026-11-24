import Testing
import Foundation
@testable import TransferKit

@Suite struct UploaderTests {
    // 25 bytes at a 10-byte part size => three parts: [10, 10, 5].
    private let totalSize: Int64 = 25

    private func makeJob() -> TransferJob {
        TransferJob(
            fileURL: URL(fileURLWithPath: "/tmp/sample.mov"),
            bucket: "b",
            key: "k",
            totalSize: totalSize
        )
    }

    private func config(maxConcurrent: Int = 2, maxRetries: Int = 3) -> UploaderConfig {
        UploaderConfig(
            partSize: 10,
            maxConcurrentParts: maxConcurrent,
            maxRetries: maxRetries,
            retryBaseSeconds: 0  // no real backoff delay in tests
        )
    }

    private func source() -> InMemoryPartSource {
        InMemoryPartSource(Data(count: Int(totalSize)))
    }

    @Test func uploadsAllPartsAndCompletes() async throws {
        let store = InMemoryTransferStore()
        let s3 = FakeS3Client()
        let uploader = Uploader(store: store, s3: s3, config: config())
        let job = makeJob()

        try await uploader.run(job, source: source())

        let saved = try #require(try await store.job(id: job.id))
        #expect(saved.state == .completed)
        #expect(saved.parts.count == 3)
        #expect(saved.parts.allSatisfy { $0.state == .uploaded && $0.eTag != nil })

        let uploadID = try #require(saved.uploadID)
        let stored = await s3.storedPartCount(uploadID: uploadID)
        let completed = await s3.isCompleted(uploadID: uploadID)
        #expect(stored == 3)
        #expect(completed)
    }

    @Test func retriesTransientThenSucceeds() async throws {
        let store = InMemoryTransferStore()
        let s3 = FakeS3Client(transientFailures: [1: 1])  // part 1 fails once
        let uploader = Uploader(store: store, s3: s3, config: config())
        let job = makeJob()

        try await uploader.run(job, source: source())

        let saved = try #require(try await store.job(id: job.id))
        #expect(saved.state == .completed)

        let attemptsPart1 = await s3.attemptCount(part: 1)
        #expect(attemptsPart1 == 2)  // one failure, then success
    }

    @Test func resumeUploadsOnlyMissingParts() async throws {
        let store = InMemoryTransferStore()
        let s3 = FakeS3Client(transientFailures: [2: 999])  // part 2 keeps failing
        let uploader = Uploader(store: store, s3: s3, config: config(maxConcurrent: 1, maxRetries: 2))
        let job = makeJob()
        let data = source()

        // First run: part 1 uploads and checkpoints, part 2 exhausts retries and throws.
        var firstRunThrew = false
        do {
            try await uploader.run(job, source: data)
        } catch {
            firstRunThrew = true
        }
        #expect(firstRunThrew)

        let afterFirst = try #require(try await store.job(id: job.id))
        let part1 = afterFirst.parts.first { $0.number == 1 }
        #expect(part1?.state == .uploaded)

        // The transient condition clears; resume from the persisted job.
        await s3.clearTransientFailures()
        try await uploader.run(afterFirst, source: data)

        let final = try #require(try await store.job(id: job.id))
        #expect(final.state == .completed)

        // Part 1 was already done — resume must not re-upload it.
        let attemptsPart1 = await s3.attemptCount(part: 1)
        #expect(attemptsPart1 == 1)
    }
}
