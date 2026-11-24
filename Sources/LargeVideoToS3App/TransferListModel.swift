import Foundation
import Observation
import TransferKit
import TransferKitAWS

/// A UI-facing snapshot of one transfer.
struct TransferItem: Identifiable {
    let id: UUID
    let name: String
    var state: TransferState
    var progress: Double  // 0...1
    var completed: Int = 0
    var total: Int = 0
    var volumePath: String? = nil  // the mounted volume the source file lives on
}

/// Owns the transfer queue and drives the engine. All UI state lives on the
/// main actor; uploads run on the `Uploader` actor and report back here.
@MainActor
@Observable
final class TransferListModel {
    private(set) var items: [TransferItem] = []

    private let store: TransferStore
    private let s3: S3Client
    private let config: AppConfig
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var volumeMonitor: VolumeMonitor?

    init(store: TransferStore, s3: S3Client, config: AppConfig) {
        self.store = store
        self.s3 = s3
        self.config = config
        startVolumeMonitoring()
    }

    private func startVolumeMonitoring() {
        volumeMonitor = VolumeMonitor { [weak self] event in
            Task { @MainActor in self?.handleVolumeEvent(event) }
        }
        volumeMonitor?.start()
    }

    /// When the drive holding an active transfer's source file is pulled, pause
    /// that transfer so it checkpoints cleanly and can resume when it returns.
    private func handleVolumeEvent(_ event: VolumeMonitor.Event) {
        guard case .disappeared(let volumePath) = event else { return }
        for item in items where item.state == .uploading && item.volumePath == volumePath {
            pause(item.id)
        }
    }

    private func volumePath(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume?.path
    }

    /// Load any jobs already persisted (so the queue survives relaunch).
    func load() async {
        guard let jobs = try? await store.allJobs() else { return }
        items = jobs.map { job in
            let done = job.parts.filter { $0.state == .uploaded }.count
            // Nothing is running at launch, so a job left "uploading" is resumable.
            let state: TransferState = job.state == .uploading ? .paused : job.state
            return TransferItem(
                id: job.id, name: job.fileURL.lastPathComponent, state: state,
                progress: job.progress, completed: done, total: job.parts.count,
                volumePath: volumePath(for: job.fileURL))
        }
    }

    func addFiles(_ urls: [URL]) {
        for url in urls {
            let job = TransferJob(
                fileURL: url,
                bucket: config.bucket,
                key: config.keyPrefix + url.lastPathComponent,
                totalSize: fileSize(url))
            items.insert(
                TransferItem(
                    id: job.id, name: url.lastPathComponent, state: .uploading, progress: 0,
                    volumePath: volumePath(for: url)),
                at: 0)
            // The uploader persists the job (with its upload id + part plan) in
            // prepared(); no need for a separate initial upsert that would race it.
            run(job)
        }
    }

    func pause(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        setState(id, .paused)
    }

    func resume(_ id: UUID) {
        Task { [weak self] in
            guard let self, let job = try? await self.store.job(id: id) else { return }
            self.run(job)
        }
    }

    func isActive(_ id: UUID) -> Bool { tasks[id] != nil }

    // MARK: - Private

    private func run(_ job: TransferJob) {
        guard tasks[job.id] == nil else { return }
        setState(job.id, .uploading)

        let uploader = Uploader(
            store: store, s3: s3,
            config: UploaderConfig(
                partSize: max(PartPlanner.minPartSize, Int64(config.partSizeMiB) * 1024 * 1024),
                maxConcurrentParts: config.maxConcurrentParts))
        let source = FilePartSource(url: job.fileURL)
        let id = job.id

        tasks[id] = Task {
            do {
                try await uploader.run(job, source: source) { done, total in
                    Task { @MainActor in self.updateProgress(id, done: done, total: total) }
                }
                self.complete(id)
            } catch is CancellationError {
                self.setState(id, .paused)
            } catch {
                FileHandle.standardError.write(Data("upload failed: \(error)\n".utf8))
                self.setState(id, .failed)
            }
            self.tasks[id] = nil
        }
    }

    private func setState(_ id: UUID, _ state: TransferState) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = state }
    }

    private func updateProgress(_ id: UUID, done: Int, total: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].completed = done
        items[i].total = total
        items[i].progress = total > 0 ? Double(done) / Double(total) : 0
    }

    private func complete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].completed = items[i].total
        items[i].progress = 1
        items[i].state = .completed
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0) ?? 0
    }
}
