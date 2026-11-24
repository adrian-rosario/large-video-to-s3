import Foundation
import Testing

@testable import TransferKit

@Suite struct TransferStoreTests {
    private func makeJob(state: TransferState = .pending) -> TransferJob {
        TransferJob(
            fileURL: URL(fileURLWithPath: "/tmp/sample.mov"),
            bucket: "test-bucket",
            key: "sample.mov",
            totalSize: 100,
            state: state
        )
    }

    @Test func upsertThenFetch() async throws {
        let store = InMemoryTransferStore()
        let job = makeJob()
        try await store.upsert(job)
        let fetched = try await store.job(id: job.id)
        #expect(fetched == job)
    }

    @Test func resumableJobsFiltersByState() async throws {
        let store = InMemoryTransferStore()
        try await store.upsert(makeJob(state: .uploading))
        try await store.upsert(makeJob(state: .paused))
        try await store.upsert(makeJob(state: .completed))
        let resumable = try await store.resumableJobs()
        #expect(resumable.count == 2)
    }

    @Test func deleteRemovesJob() async throws {
        let store = InMemoryTransferStore()
        let job = makeJob()
        try await store.upsert(job)
        try await store.delete(id: job.id)
        let fetched = try await store.job(id: job.id)
        #expect(fetched == nil)
    }
}
