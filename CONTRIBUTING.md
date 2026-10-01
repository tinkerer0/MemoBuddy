# Contributing to MemoBuddy

MemoBuddy aims to stay small, light, and easy to understand. Focused bug fixes and lightweight improvements are welcome.

## Before changing code

- Search existing issues before opening a new one.
- For larger behavior changes, open an issue first so the interaction and weight tradeoffs can be discussed.
- Never include real memo contents, custom character files you cannot redistribute, credentials, personal paths, or other private data.

## Local checks

MemoBuddy 1.0 is built with Tauri 2. You need Node.js 20 or later and Rust (rustup); on macOS also the Xcode command line tools. macOS 13 or later, Windows 10 or later for development (the Microsoft Store package needs Windows 11, which includes WebView2).

```bash
npm install
npx tsc --noEmit
npm test
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri dev
```

For UI changes, check white and dark themes, multiple memo sizes, screen edges, and both text and drawing modes, on macOS and, if you can, Windows. Keep the character context menu compact.

## Releases

A user-facing MemoBuddy update is complete only after all of these steps:

1. Update the semantic version in `package.json`, `src-tauri/tauri.conf.json` and `src-tauri/Cargo.toml`.
2. Run the local checks above and `npm run tauri build`.
3. Push the release commit to `main` and wait for CI to pass.
4. Create the matching `vX.Y.Z` tag and GitHub Release.
5. Verify that GitHub's automatically generated source archives are available.

Pushing a commit alone does not notify installed apps. The older Swift
MemoPet (v0.4.x) checks GitHub Releases, so publish a numbered Release only for
a build intended for users. Store builds follow `docs/RELEASE.md`. Do not
attach a prebuilt app while MemoBuddy is distributed as source code only.

## Pull requests

Keep each pull request focused, explain the user-visible reason for the change, and include tests for data handling or pure logic. Generated build products (`dist/`, `src-tauri/target/`) must not be committed.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
