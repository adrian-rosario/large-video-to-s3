import CoreData
import Foundation

/// A `TransferStore` backed by Core Data (programmatic model). Every access runs
/// on a private background context's queue via `context.perform`; the type is
/// `@unchecked Sendable` because that queue is the single point of access to all
/// managed state, and only value types cross the boundary.
public final class CoreDataTransferStore: TransferStore, @unchecked Sendable {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    /// `url` points at a SQLite file; pass nil for an in-memory store (tests).
    public init(url: URL?) throws {
        self.container = try CoreDataStack.makeContainer(url: url)
        self.context = container.newBackgroundContext()
        self.context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    public func upsert(_ job: TransferJob) async throws {
        try await context.perform { [context] in
            let entity =
                try Self.fetch(id: job.id, in: context)
                ?? NSEntityDescription.insertNewObject(forEntityName: "JobEntity", into: context)
            Self.write(job, into: entity, context: context)
            try context.save()
        }
    }

    public func job(id: UUID) async throws -> TransferJob? {
        try await context.perform { [context] in
            try Self.fetch(id: id, in: context).map(Self.read)
        }
    }

    public func allJobs() async throws -> [TransferJob] {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: "JobEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return try context.fetch(request).map(Self.read)
        }
    }

    public func delete(id: UUID) async throws {
        try await context.perform { [context] in
            if let entity = try Self.fetch(id: id, in: context) {
                context.delete(entity)
                try context.save()
            }
        }
    }

    // MARK: - Fetch

    private static func fetch(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "JobEntity")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: - Domain -> managed

    private static func write(
        _ job: TransferJob, into entity: NSManagedObject, context: NSManagedObjectContext
    ) {
        entity.setValue(job.id, forKey: "id")
        entity.setValue(job.fileURL.absoluteString, forKey: "fileURL")
        entity.setValue(job.bucket, forKey: "bucket")
        entity.setValue(job.key, forKey: "key")
        entity.setValue(job.totalSize, forKey: "totalSize")
        entity.setValue(job.uploadID, forKey: "uploadID")
        entity.setValue(job.state.rawValue, forKey: "state")
        entity.setValue(job.createdAt, forKey: "createdAt")
        entity.setValue(job.updatedAt, forKey: "updatedAt")

        // Replace the part set wholesale — simplest correct upsert.
        if let existing = entity.value(forKey: "parts") as? Set<NSManagedObject> {
            existing.forEach(context.delete)
        }
        let parts = job.parts.map { part -> NSManagedObject in
            let pe = NSEntityDescription.insertNewObject(forEntityName: "PartEntity", into: context)
            pe.setValue(part.number, forKey: "number")
            pe.setValue(part.offset, forKey: "offset")
            pe.setValue(part.size, forKey: "size")
            pe.setValue(part.state.rawValue, forKey: "state")
            pe.setValue(part.eTag, forKey: "eTag")
            return pe
        }
        entity.setValue(Set(parts), forKey: "parts")
    }

    // MARK: - Managed -> domain

    private static func read(_ entity: NSManagedObject) -> TransferJob {
        let partSet = (entity.value(forKey: "parts") as? Set<NSManagedObject>) ?? []
        let parts = partSet.compactMap(readPart).sorted { $0.number < $1.number }
        return TransferJob(
            id: entity.value(forKey: "id") as? UUID ?? UUID(),
            fileURL: URL(string: str(entity, "fileURL")) ?? URL(fileURLWithPath: "/"),
            bucket: str(entity, "bucket"),
            key: str(entity, "key"),
            totalSize: int64(entity, "totalSize"),
            uploadID: entity.value(forKey: "uploadID") as? String,
            state: TransferState(rawValue: str(entity, "state")) ?? .pending,
            parts: parts,
            createdAt: entity.value(forKey: "createdAt") as? Date ?? Date(),
            updatedAt: entity.value(forKey: "updatedAt") as? Date ?? Date()
        )
    }

    private static func readPart(_ e: NSManagedObject) -> TransferPart? {
        guard let number = (e.value(forKey: "number") as? NSNumber)?.intValue else { return nil }
        return TransferPart(
            number: number,
            offset: int64(e, "offset"),
            size: int64(e, "size"),
            state: PartState(rawValue: str(e, "state")) ?? .pending,
            eTag: e.value(forKey: "eTag") as? String
        )
    }

    // Core Data returns scalar numbers as NSNumber via KVC.
    private static func int64(_ e: NSManagedObject, _ key: String) -> Int64 {
        (e.value(forKey: key) as? NSNumber)?.int64Value ?? 0
    }

    private static func str(_ e: NSManagedObject, _ key: String) -> String {
        e.value(forKey: key) as? String ?? ""
    }
}
