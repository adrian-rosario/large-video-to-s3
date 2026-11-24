# large-video-to-s3 — Plan

A native macOS app (Swift / SwiftUI) that reliably uploads large video files to Amazon S3 —
surviving network drops, drive disconnects, app crashes, and restarts. Built as a clean,
idiomatic **reference implementation** of resilient large-file transfer on Apple platforms.

## Why this exists

Plenty of tools move files to S3 (the AWS CLI, rclone, s5cmd, Transmit, Cyberduck). What's thin
is an **open-source, native-macOS reference** that does the full Apple-idiomatic treatment —
security-scoped bookmarks, DiskArbitration, background URLSession, Core Data transfer state, and
Swift 6 structured concurrency — the way a real production macOS data-collection app works. The
value here isn't novelty; it's a clear demonstration of *how* to build this well.

## Design principle: resilient core first

Build the hard, interesting part first — the transfer engine that can be interrupted at any point
and pick up cleanly — and prove it with tests before any UI. Everything else (UI, disconnect
handling, headless mode) decorates a core that already works.

## Architecture

- **`TransferKit`** — a Swift Package (the engine). No UI, no AppKit. Platform-testable.
  - `S3Client` behind a protocol → real impl uses **AWS SDK for Swift**; a fake impl drives tests.
  - `TransferStore` behind a protocol → start with a Codable JSON checkpoint; swap in **Core Data**
    later without touching the engine. (Protocol-oriented + dependency injection by design — it's
    also exactly the "modular, testable, clear module boundaries" the target role asks for.)
  - `Uploader` — an **actor** owning the part-state map so updates are race-free; a **bounded
    `TaskGroup`** uploads N parts in parallel.
- **`LargeVideoToS3`** — a thin SwiftUI app target (added in Xcode) that consumes `TransferKit`.
- **Swift 6 language mode + strict concurrency ON from day one.** That's half the point — it turns
  "I haven't shipped under strict concurrency" into "I built this under it."

## Milestones

- **M0 — Scaffold.** Package.swift, domain model (`TransferJob` / `TransferPart`, state enums),
  `TransferStore` + `S3Client` protocols, a fake S3 client, first passing test. Compiles, tests green.
- **M1 — Resilient core (the MVP / "it works" bar).** Multipart upload of one local file to a real
  bucket: initiate → bounded-parallel `UploadPart` → record each ETag → complete. Retry with
  backoff + jitter. JSON checkpoint persistence. **Resume after restart**: reload checkpoint,
  `ListParts` to reconcile with S3, re-drive only missing parts. `AbortMultipartUpload` on give-up.
  Driven by a tiny CLI + unit/integration tests. ← *When this passes, the project "works."*
- **M2 — Core Data store.** Implement `TransferStore` on Core Data (`TransferJob` / `TransferPart`
  entities), swap it in behind the protocol. Background-context writes; `objectID` across contexts.
- **M3 — SwiftUI app.** Transfer queue, per-file progress, pause/resume. File/drive picker that
  persists a **security-scoped bookmark** so transfers resume after relaunch.
- **M4 — Drive disconnect.** Register a **DiskArbitration** session; on disappear, checkpoint + pause
  and surface it; on reappear (match by volume UUID), reconcile and resume missing parts.
- **M5 — Survive app death.** Move transfers onto a **background URLSession** so the OS keeps going
  when the app is suspended/killed; reconcile on next launch. (Note: background sessions upload via
  presigned URLs rather than the SDK's in-process client — plan a small `PresignedPartSource` for this.)
- **M6 — Headless variant.** A **launchd** agent that runs the engine with no UI (maps directly to
  the systemd supervision model — KeepAlive ≈ Restart=always, ThrottleInterval ≈ StartLimitInterval).

## Repository layout (target, open-source-ready)

Keep the **engine (SPM library) separate from the app**, so others can depend on `TransferKit`
without pulling in the UI. Documentation lives in `docs/`; the root carries the standard OSS files.

```
large-video-to-s3/
├── README.md               # what it is, a screenshot/gif, quickstart, build status, roadmap link
├── LICENSE                 # MIT or Apache-2.0 (decide before going public)
├── CONTRIBUTING.md         # how to build, run tests, open a PR
├── CODE_OF_CONDUCT.md      # standard boilerplate
├── CHANGELOG.md            # keep-a-changelog format
├── PLAN.md                 # this roadmap (can move under docs/ once README matures)
├── .gitignore
├── .github/
│   └── workflows/ci.yml    # build + test on a macOS runner (GitHub Actions)
├── Package.swift           # TransferKit manifest (the library)
├── Sources/
│   └── TransferKit/
│       ├── Model/          # TransferJob, TransferPart, state enums
│       ├── Store/          # TransferStore protocol, JSONTransferStore, CoreDataTransferStore
│       ├── S3/             # S3Client protocol, AWSS3Client, PresignedPartSource
│       ├── Engine/         # Uploader actor, TaskGroup orchestration, retry/backoff
│       └── Platform/       # DiskArbitration watcher, security-scoped bookmarks, background URLSession
├── Tests/
│   └── TransferKitTests/   # unit + integration against a fake S3; interrupt/resume tests
├── Apps/
│   └── LargeVideoToS3/     # the SwiftUI app (Xcode project that consumes TransferKit)
├── Tools/
│   └── lvs3-cli/           # small CLI that drives TransferKit — the M1 test driver / demo
├── docs/
│   ├── architecture.md     # the design + the seven problem areas, with a diagram
│   ├── resilience.md       # checkpoint/detect/resume, the multipart lifecycle, edge cases
│   ├── setup.md            # AWS bucket + scoped IAM + lifecycle-rule setup
│   └── images/             # screenshots, diagrams
└── scripts/
    └── setup-test-bucket.sh  # optional: create the scoped test bucket + IAM + lifecycle rule
```

Documentation that makes it credible as OSS: a **README** that frames it as a reference
implementation (with a short demo gif once the app exists), a **LICENSE**, a **CONTRIBUTING** guide
so it looks maintained, and **`docs/architecture.md`** — which doubles as your interview artifact
("here's the design and why each decision"). Write `docs/` as you build each milestone, not at the end.

## Tech choices

- **AWS SDK for Swift** (`aws-sdk-swift`, `AWSS3`) for the S3 operations — idiomatic, handles SigV4,
  keeps focus on the resilience logic instead of reimplementing signing.
- **Swift Testing** (+ XCTest where needed) for tests.
- macOS 14+ (Observation, modern SwiftUI), Swift 6 language mode.

## Credentials & cost safety (do this before M1)

- Use a **dedicated throwaway test bucket**, never HFDN production.
- A **least-privilege IAM user/role** scoped to just that bucket's multipart actions
  (`s3:PutObject`, `CreateMultipartUpload`, `UploadPart`, `ListParts`, `CompleteMultipartUpload`,
  `AbortMultipartUpload`, `ListMultipartUploads`, `AbortMultipartUpload`).
- Credentials via a **named AWS profile or env vars only** — never committed. `.gitignore` covers it.
- Add an **S3 lifecycle rule to auto-abort incomplete multipart uploads after ~1 day**, so testing
  interrupted transfers never quietly accrues orphaned-part storage cost.

## Definition of done — MVP (through M1)

Upload a multi-GB file to S3; kill the process mid-transfer; relaunch; it reconciles with S3 and
finishes without re-uploading completed parts, and the final object is intact. Tests cover the
interrupt/resume path against a fake S3 client so the logic is provable without the network.

## Open decisions

1. AWS SDK for Swift for the S3 layer (recommended) — or hand-rolled presigned URLs + URLSession?
2. Start persistence as JSON-checkpoint and migrate to Core Data at M2 (recommended) — or go Core
   Data from the start?
3. Do you have (or want me to spec) a dedicated test bucket + scoped IAM profile before M1?
