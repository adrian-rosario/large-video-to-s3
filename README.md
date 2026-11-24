# large-video-to-s3

A native macOS app (Swift / SwiftUI) that reliably uploads large video files to Amazon S3 —
surviving network drops, drive disconnects, app crashes, and restarts.

Built as a clean, idiomatic **reference implementation** of resilient large-file transfer on Apple
platforms: Swift 6 structured concurrency, DiskArbitration, background URLSession, and Core Data
transfer state.

> **Status:** working end to end. The engine, the `lvs3` CLI, and the SwiftUI app all run against
> real S3 — a multi-GB upload can be interrupted and resumes from its last checkpoint. See
> [the roadmap](docs/roadmap.md) for the full milestone history.

## Design & architecture

**Layered so the engine owes nothing to AWS or the UI.** The core is a dependency-free Swift package;
everything platform- or vendor-specific sits in a layer above it, behind a protocol.

```
TransferKit            core engine — protocols, Uploader actor, stores, platform helpers (no AWS, no UI)
├─ TransferKitAWS      the real S3 client (AWS SDK for Swift) behind TransferKit's S3Client protocol
├─ lvs3                command-line driver (JSON-checkpoint store)
└─ LargeVideoToS3App   SwiftUI app (Core Data store, live progress, pause/resume)
```

**The resilience model is one idea applied everywhere: _checkpoint → detect → resume._** A file is
split into parts and uploaded through a bounded `TaskGroup`; as each part is confirmed, its ETag is
**checkpointed** to the store. On restart the engine reconciles its checkpoint against what S3
actually holds (`ListParts`) and re-drives **only the missing parts**. Every step is idempotent, so
retrying a part that may already be done is always safe — recovery logic doesn't have to be perfect,
just safe.

**Protocol-oriented and dependency-injected, so it's testable without a network.** The engine talks
only to two protocols — `S3Client` and `TransferStore`. Tests run the full upload/retry/resume logic
against an in-memory `FakeS3Client` with failure injection, so the suite is fast, deterministic, and
offline; the AWS SDK is one interchangeable implementation of the same protocol.

**Concurrency (Swift 6 strict mode).** The `Uploader` is an actor that owns part state; parts upload
in parallel under a bounded `TaskGroup`; failures retry with exponential backoff + jitter; and
**pause** is cooperative cancellation — cancelling the task drains in-flight parts, checkpoints them,
and stops, so **resume** is just the normal resume path.

**Pluggable persistence.** The same `TransferStore` protocol is implemented three ways — in-memory
(tests), a JSON checkpoint file (CLI), and a programmatic **Core Data** model with a
`Job → Part` relationship (app) — swappable without touching the engine.

**Native Apple integration.** `VolumeMonitor` uses **DiskArbitration** to pause a transfer when its
source drive is pulled and resume when it returns; `BackgroundUploader` + `PresignedURLProvider`
demonstrate out-of-process transfer via a **background URLSession** PUT to a presigned S3 URL.

## Build & test

```sh
swift build
swift test
```

Requires a recent Swift 6 toolchain (Xcode 16+). The package targets macOS 14+ and builds in the
Swift 6 language mode with strict concurrency checking on. To run against your own AWS account, see
[docs/setup.md](docs/setup.md).

## Roadmap

See [the roadmap](docs/roadmap.md) — resilient core (multipart + resume) → Core Data store → SwiftUI
app → DiskArbitration drive-disconnect → background-URLSession upload.

## License

[MIT](LICENSE) © 2026 Adrian Rosario
