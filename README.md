# large-video-to-s3

A native macOS app (Swift / SwiftUI) that reliably uploads large video files to Amazon S3 —
surviving network drops, drive disconnects, app crashes, and restarts.

Built as a clean, idiomatic **reference implementation** of resilient large-file transfer on Apple
platforms: Swift 6 structured concurrency, security-scoped bookmarks, DiskArbitration, background
URLSession, and Core Data transfer state.

> **Status:** early. The transfer engine (`TransferKit`) is being built core-first, with a green
> test baseline before any UI. See [the roadmap](docs/roadmap.md) for scope and milestones.

## Architecture

- **`TransferKit`** — the engine, as a Swift package. No UI. Fully testable.
  - `S3Client` protocol (real impl via the AWS SDK; a fake for tests)
  - `TransferStore` protocol (in-memory now; Core Data next)
  - `Uploader` actor — owns part state; bounded-parallel part uploads
- **`LargeVideoToS3`** — a thin SwiftUI app that consumes `TransferKit` (added later).

## Build & test

```sh
swift build
swift test
```

Requires a recent Swift 6 toolchain (Xcode 16+). The package targets macOS 14+ and builds in the
Swift 6 language mode with strict concurrency checking on.

## Roadmap

See [the roadmap](docs/roadmap.md). Short version: resilient core (multipart + resume) → Core Data store →
SwiftUI app → drive-disconnect handling → survive-app-death → headless launchd variant.

## License

TBD before the repository is made public.
