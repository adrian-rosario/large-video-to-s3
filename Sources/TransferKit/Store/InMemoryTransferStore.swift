import Foundation

/// A `TransferStore` kept entirely in memory. Used for tests and previews, and
/// as the reference behavior the Core Data store must match.
public actor InMemoryTransferStore: TransferStore {
    private var jobs: [UUID: TransferJob] = [:]

    public init() {}

    public func upsert(_ job: TransferJob) async throws {
        jobs[job.id] = job
    }

    public func job(id: UUID) async throws -> TransferJob? {
        jobs[id]
    }

    public func allJobs() async throws -> [TransferJob] {
        jobs.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(id: UUID) async throws {
        jobs.removeValue(forKey: id)
    }
}
