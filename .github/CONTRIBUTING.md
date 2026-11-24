# Contributing

## Build & test

```sh
swift build
swift test                      # run the suite
swift test --enable-code-coverage
swift format lint -r Sources Tests   # check style (CI enforces this)
swift format -i -r Sources Tests     # auto-format in place
```

## Code conventions

These keep the codebase readable and reviewable — the point of the project.

- **One primary type per file**, named after that type (`Uploader.swift` holds `Uploader`).
- **Small files.** Aim for roughly 150 lines or fewer. If a file grows past that, it's usually
  doing too much — split by responsibility (model vs. store vs. engine vs. platform).
- **Clear, concise names.** Descriptive but not verbose: `TransferPart`, not
  `MultipartUploadPartDescriptor`. No Hungarian prefixes, no redundant suffixes.
- **Protocol-oriented + dependency injection.** The engine depends on `S3Client` / `TransferStore`
  protocols, never concrete types — so everything is swappable and testable.
- **Swift 6 strict concurrency.** Value types are `Sendable`; shared mutable state lives in actors.
  No `@unchecked Sendable` without a comment justifying it.
- **Every behavior has a test.** New logic lands with unit tests against the fakes; network code is
  proven against `FakeS3Client` so the suite stays fast and offline.
- **Document the why.** Short doc comments on public types explain intent, not mechanics.

## Pull requests

- Keep PRs focused and small enough to review in one sitting.
- CI (build, test, format lint) must pass before merge.
- Write a one-line summary of *what* changed and *why* in the PR description.
