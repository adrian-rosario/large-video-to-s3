import Foundation
import Testing

@testable import TransferKit

@Suite struct FakeS3ClientTests {
    @Test func multipartLifecycle() async throws {
        let s3 = FakeS3Client()
        let id = try await s3.createMultipartUpload(bucket: "b", key: "k")

        _ = try await s3.uploadPart(
            bucket: "b", key: "k", uploadID: id, partNumber: 1,
            data: Data(repeating: 0, count: 10))
        _ = try await s3.uploadPart(
            bucket: "b", key: "k", uploadID: id, partNumber: 2,
            data: Data(repeating: 1, count: 5))

        let parts = try await s3.listParts(bucket: "b", key: "k", uploadID: id)
        #expect(parts.count == 2)
        #expect(parts.map(\.number) == [1, 2])

        try await s3.completeMultipartUpload(bucket: "b", key: "k", uploadID: id, parts: parts)
        let completed = await s3.isCompleted(uploadID: id)
        #expect(completed)
    }

    @Test func injectedTransientFailureThenSuccess() async throws {
        // Part 1 fails once, then succeeds — the shape of a retryable upload.
        let s3 = FakeS3Client(transientFailures: [1: 1])
        let id = try await s3.createMultipartUpload(bucket: "b", key: "k")

        var threwOnFirstAttempt = false
        do {
            _ = try await s3.uploadPart(bucket: "b", key: "k", uploadID: id, partNumber: 1, data: Data([0]))
        } catch {
            threwOnFirstAttempt = true
        }
        #expect(threwOnFirstAttempt)

        let eTag = try await s3.uploadPart(
            bucket: "b", key: "k", uploadID: id, partNumber: 1, data: Data([0]))
        #expect(!eTag.isEmpty)

        let stored = await s3.storedPartCount(uploadID: id)
        #expect(stored == 1)
    }

    @Test func abortDiscardsUpload() async throws {
        let s3 = FakeS3Client()
        let id = try await s3.createMultipartUpload(bucket: "b", key: "k")
        try await s3.abortMultipartUpload(bucket: "b", key: "k", uploadID: id)

        var threw = false
        do {
            _ = try await s3.listParts(bucket: "b", key: "k", uploadID: id)
        } catch {
            threw = true
        }
        #expect(threw)
    }
}
