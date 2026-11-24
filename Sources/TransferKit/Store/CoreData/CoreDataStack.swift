import CoreData
import Foundation

/// Builds the Core Data stack in code (no `.xcdatamodeld` file), so the model
/// lives in readable Swift and the package needs no bundled resources.
///
/// Model: a `JobEntity` with a to-many `parts` relationship to `PartEntity`
/// (cascade delete), mirrored by an inverse `job` relationship.
enum CoreDataStack {
    static func makeModel() -> NSManagedObjectModel {
        let job = NSEntityDescription()
        job.name = "JobEntity"

        let part = NSEntityDescription()
        part.name = "PartEntity"

        job.properties = jobAttributes()
        part.properties = partAttributes()

        let (jobToParts, partToJob) = relationship(job: job, part: part)
        job.properties.append(jobToParts)
        part.properties.append(partToJob)

        let model = NSManagedObjectModel()
        model.entities = [job, part]
        return model
    }

    /// A container over a SQLite file at `url`, or in-memory when `url` is nil.
    static func makeContainer(url: URL?) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: "TransferKit", managedObjectModel: makeModel())

        let description = NSPersistentStoreDescription()
        if let url {
            description.url = url
            description.type = NSSQLiteStoreType
        } else {
            description.type = NSInMemoryStoreType
        }
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    // MARK: - Model building helpers

    private static func attribute(
        _ name: String, _ type: NSAttributeType, optional: Bool = false
    ) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        return a
    }

    private static func jobAttributes() -> [NSPropertyDescription] {
        [
            attribute("id", .UUIDAttributeType),
            attribute("fileURL", .stringAttributeType),
            attribute("bucket", .stringAttributeType),
            attribute("key", .stringAttributeType),
            attribute("totalSize", .integer64AttributeType),
            attribute("uploadID", .stringAttributeType, optional: true),
            attribute("state", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ]
    }

    private static func partAttributes() -> [NSPropertyDescription] {
        [
            attribute("number", .integer32AttributeType),
            attribute("offset", .integer64AttributeType),
            attribute("size", .integer64AttributeType),
            attribute("state", .stringAttributeType),
            attribute("eTag", .stringAttributeType, optional: true),
        ]
    }

    private static func relationship(
        job: NSEntityDescription, part: NSEntityDescription
    ) -> (toParts: NSRelationshipDescription, toJob: NSRelationshipDescription) {
        let toParts = NSRelationshipDescription()
        toParts.name = "parts"
        toParts.destinationEntity = part
        toParts.minCount = 0
        toParts.maxCount = 0  // 0 == to-many
        toParts.deleteRule = .cascadeDeleteRule

        let toJob = NSRelationshipDescription()
        toJob.name = "job"
        toJob.destinationEntity = job
        toJob.minCount = 0
        toJob.maxCount = 1
        toJob.deleteRule = .nullifyDeleteRule

        toParts.inverseRelationship = toJob
        toJob.inverseRelationship = toParts
        return (toParts, toJob)
    }
}
