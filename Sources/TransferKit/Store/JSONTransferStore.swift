import Foundation

/// A `TransferStore` persisted to a JSON file, so jobs (and their checkpointed
/// part state) survive a process restart — the CLI uses this to resume uploads
/// across runs. The Core Data store (M2) will replace it in the app.
public actor JSONTransferStore: TransferStore {
    private let url: URL
    private var jobs: [UUID: TransferJob]

    public init(url: URL) {
        self.url = url
        self.jobs = Self.load(from: url)
    }

    public func upsert(_ job: TransferJob) async throws {
        jobs[job.id] = job
        try persist()
    }

    public func job(id: UUID) async throws -> TransferJob? {
        jobs[id]
    }

    public func allJobs() async throws -> [TransferJob] {
        jobs.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(id: UUID) async throws {
        jobs.removeValue(forKey: id)
        try persist()
    }

    // MARK: - Disk

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Array(jobs.values))
        try data.write(to: url, options: .atomic)
    }

    private static func load(from url: URL) -> [UUID: TransferJob] {
        guard let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([TransferJob].self, from: data)
        else { return [:] }
        return Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
