import Foundation

/// Persistence for upload jobs. The engine talks only to this protocol, so the
/// backing store (in-memory for tests, Core Data in the app) is swappable.
///
/// All methods are `async` and the type is `Sendable` so implementations can be
/// actors or wrap a background Core Data context without leaking isolation.
public protocol TransferStore: Sendable {
    /// Insert or update a job (keyed by `id`).
    func upsert(_ job: TransferJob) async throws

    /// Fetch one job by id, or nil if unknown.
    func job(id: UUID) async throws -> TransferJob?

    /// All jobs, newest first.
    func allJobs() async throws -> [TransferJob]

    /// Jobs that can be resumed (uploading or paused) — used on relaunch.
    func resumableJobs() async throws -> [TransferJob]

    /// Remove a job.
    func delete(id: UUID) async throws
}

public extension TransferStore {
    /// Default: derive resumable jobs from all jobs. Stores backed by a query
    /// engine can override this for efficiency.
    func resumableJobs() async throws -> [TransferJob] {
        try await allJobs().filter { $0.state == .uploading || $0.state == .paused }
    }
}
