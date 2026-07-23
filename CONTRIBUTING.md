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

## Pull requests

Keep each pull request focused, explain the user-visible reason for the change, and include tests for data handling or pure logic. Generated build products belong in `dist/` and must not be committed.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
