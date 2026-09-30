# MemoPet

A tiny notebook that floats above your apps, for macOS and Windows.

Click the little character to open a memo. Type or draw, click elsewhere, and it saves and gets out of your way.

- Tabs for multiple notes (add, rename, drag to reorder, delete with confirmation)
- Text and drawing in the same note (pen and round eraser)
- Automatic local saving with a backup and damaged-file recovery
- Three built-in characters or your own GIF/PNG/JPEG/WebP, in three sizes
- Menu bar / system tray controls, white or dark theme
- Three pen widths and eraser sizes (right-click the pen or eraser)
- No account, ads, tracking or network use

## Get MemoPet

Mac App Store and Microsoft Store versions are being prepared. Until they are out, build it from source (below).

Windows testers: open the latest successful [CI run](https://github.com/tinkerer0/MemoPet/actions/workflows/ci.yml) and download the `MemoPet-windows-installer` artifact (GitHub sign-in required, kept for 90 days). It is not code-signed yet, so Windows SmartScreen asks first: choose **More info → Run anyway**. It installs for the current user without administrator rights.

The original macOS-only Swift/AppKit MemoPet (v0.4.1 and earlier) stays in this repository's history: `git checkout v0.4.1`.

## How it is built

Built with [Tauri 2](https://tauri.app). The shared UI and storage run on both platforms; only window control is platform-specific (`src-tauri/src/platform/`). On macOS the character is a native transparent panel and nothing uses private APIs (`macOSPrivateApi` is off), so the app can be submitted to the Mac App Store.

## Develop

Requirements: Node.js 20+, Rust (rustup), and on macOS the Xcode command line tools.

```sh
npm install
npm run tauri dev        # run
npm test                 # frontend unit tests (vitest)
cargo test --manifest-path src-tauri/Cargo.toml   # Rust tests
./compat/check.sh        # notes.json compatibility with the Swift MemoPet (macOS)
```

`compat/check.sh` reads notes with the real Swift `MemoPetCore`, so it needs the Swift source next to this folder as `memo_pet`, for example `git worktree add ../memo_pet v0.4.1`.

## Release

See [docs/RELEASE.md](docs/RELEASE.md) (Mac App Store and Microsoft Store), [docs/STORE_LISTING.md](docs/STORE_LISTING.md) and [docs/PRIVACY.md](docs/PRIVACY.md).

## Data

Notes are stored as `notes.json` (format version 4, readable by the Swift MemoPet) in the app data folder, with `notes.backup.json`. Strokes may carry an optional `width`; older readers ignore it.

## Feedback

제가 이런 분야를 접한 지 얼마 안 돼서 부족한 점이 많습니다. 고칠 점이나 알려주실 내용이 있다면 issue나 PR로 남겨주시면 너무 감사하겠습니다.

I am still new to this, so there is a lot to improve. Issues and pull requests with fixes or suggestions are very welcome.

## License

MIT — see [LICENSE](LICENSE).
