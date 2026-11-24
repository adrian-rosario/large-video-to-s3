import Foundation
import Testing

@testable import TransferKit

@Suite struct StorageTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func filePartSourceReadsExactRange() async throws {
        let url = tempURL()
        try Data("0123456789".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = FilePartSource(url: url)
        let chunk = try await source.read(offset: 2, size: 3)
        #expect(String(decoding: chunk, as: UTF8.self) == "234")
    }

    @Test func jsonStorePersistsAcrossInstances() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let job = TransferJob(
            fileURL: URL(fileURLWithPath: "/tmp/x.mov"),
            bucket: "b", key: "k", totalSize: 42
        )

        let writer = JSONTransferStore(url: url)
        try await writer.upsert(job)

        // A fresh store at the same path should load the persisted job.
        let reader = JSONTransferStore(url: url)
        let loaded = try await reader.job(id: job.id)
        #expect(loaded == job)
    }
}
