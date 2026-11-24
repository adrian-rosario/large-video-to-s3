import Foundation
import Testing
@testable import TransferKit

@Suite struct CoreDataTransferStoreTests {
    private func makeJob(state: TransferState = .uploading) -> TransferJob {
        TransferJob(
            fileURL: URL(fileURLWithPath: "/tmp/sample.mov"),
            bucket: "b",
            key: "k",
            totalSize: 30,
            uploadID: "up-1",
            state: state,
            parts: [
                TransferPart(number: 1, offset: 0, size: 10, state: .uploaded, eTag: "\"e1\""),
                TransferPart(number: 2, offset: 10, size: 10, state: .pending),
            ]
        )
    }

    @Test func roundTripWithParts() async throws {
        let store = try CoreDataTransferStore(url: nil)
        let job = makeJob()
        try await store.upsert(job)

        let loaded = try #require(try await store.job(id: job.id))
        #expect(loaded.bucket == "b")
        #expect(loaded.key == "k")
        #expect(loaded.totalSize == 30)
        #expect(loaded.uploadID == "up-1")
        #expect(loaded.parts.map(\.number) == [1, 2])
        #expect(loaded.parts[0].state == .uploaded)
        #expect(loaded.parts[0].eTag == "\"e1\"")
        #expect(loaded.parts[1].state == .pending)
    }

    @Test func resumableJobsFiltersByState() async throws {
        let store = try CoreDataTransferStore(url: nil)
        try await store.upsert(makeJob(state: .uploading))
        try await store.upsert(makeJob(state: .paused))
        try await store.upsert(makeJob(state: .completed))

        let resumable = try await store.resumableJobs()
        #expect(resumable.count == 2)
    }

    @Test func deleteRemovesJob() async throws {
        let store = try CoreDataTransferStore(url: nil)
        let job = makeJob()
        try await store.upsert(job)
        try await store.delete(id: job.id)

        let got = try await store.job(id: job.id)
        #expect(got == nil)
    }

    @Test func persistsAcrossInstances() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        let job = makeJob()
        let writer = try CoreDataTransferStore(url: url)
        try await writer.upsert(job)

        let reader = try CoreDataTransferStore(url: url)
        let loaded = try #require(try await reader.job(id: job.id))
        #expect(loaded.parts.count == 2)
        #expect(loaded.uploadID == "up-1")
    }
}
