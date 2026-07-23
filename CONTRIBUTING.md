# Contributing to MemoPet

MemoPet aims to stay small, native, and easy to understand. Focused bug fixes and lightweight improvements are welcome.

## Before changing code

- Search existing issues before opening a new one.
- For larger behavior changes, open an issue first so the interaction and weight tradeoffs can be discussed.
- Never include real memo contents, custom character files you cannot redistribute, credentials, personal paths, or other private data.

## Local checks

MemoPet requires macOS 13 or later and Swift 5.9 or later.

```bash
swift test
./scripts/package-release.sh
open dist/MemoPet.app
```

For UI changes, check light and dark appearance, multiple memo sizes, screen edges, and both text and drawing modes. Keep the character context menu compact.

## Releases

A user-facing MemoPet update is complete only after all of these steps:

1. Update the semantic version and build number in `Support/Info.plist`.
2. Run `swift test` and `./scripts/package-release.sh`.
3. Push the release commit to `main` and wait for CI to pass.
4. Create the matching `vX.Y.Z` tag and GitHub Release.
5. Attach the verified `dist/MemoPet.zip` archive to the Release.

Pushing a commit alone does not notify installed apps. Publish a numbered
GitHub Release only for a build intended for users, so development commits do
not produce unnecessary update notices.

## Pull requests

Keep each pull request focused, explain the user-visible reason for the change, and include tests for data handling or pure logic. Generated build products belong in `dist/` and must not be committed.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
