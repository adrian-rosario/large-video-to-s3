import Foundation
import TransferKit
import TransferKitAWS

/// `lvs3 <file-path> [object-key]` — uploads a file to the configured S3 bucket,
/// resuming automatically if a previous run for the same key was interrupted.
@main
struct LVS3 {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("usage: lvs3 <file-path> [object-key]")
            exit(2)
        }

        let fileURL = URL(fileURLWithPath: args[1])
        let config = try AppConfig.load()
        let key = args.count >= 3 ? args[2] : config.keyPrefix + fileURL.lastPathComponent
        let size = try fileSize(fileURL)

        let store = JSONTransferStore(url: URL(fileURLWithPath: ".lvs3-state.json"))
        let s3 = try AWSS3Client(region: config.region)
        let uploader = Uploader(
            store: store,
            s3: s3,
            config: UploaderConfig(
                partSize: max(PartPlanner.minPartSize, Int64(config.partSizeMiB) * 1024 * 1024),
                maxConcurrentParts: config.maxConcurrentParts))

        // Resume an unfinished job for this key, otherwise start a new one.
        let existing = try await store.allJobs().first {
            $0.bucket == config.bucket && $0.key == key && $0.state != .completed
        }
        let job =
            existing
            ?? TransferJob(fileURL: fileURL, bucket: config.bucket, key: key, totalSize: size)

        if existing != nil {
            let done = job.parts.filter { $0.state == .uploaded }.count
            print("Resuming \(key) — \(done)/\(job.parts.count) parts already uploaded…")
        } else {
            print("Uploading \(key) (\(size) bytes)…")
        }

        try await uploader.run(job, source: FilePartSource(url: fileURL)) { done, total in
            let pct = total > 0 ? done * 100 / total : 0
            print("\r  \(done)/\(total) parts (\(pct)%)   ", terminator: "")
            fflush(stdout)
        }
        print("")  // finish the progress line
        print("✔ Done: s3://\(config.bucket)/\(key)")
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? Int64) ?? 0
    }
}
