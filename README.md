# MemoBuddy

(Formerly MemoPet.)

A tiny notebook that floats above your apps, for macOS and Windows.

Click the little character to open a memo. Type or draw, click elsewhere, and it saves and gets out of your way.

- Tabs for multiple notes (add, rename, drag to reorder, delete with confirmation)
- Text and drawing in the same note (pen and round eraser)
- Automatic local saving with a backup and damaged-file recovery
- Nine characters (a writing bear, a penguin, a ghost, a shiba, a humble pebble, planets and a moon), in three sizes
- Any photo or GIF you like as the pet: right-click the pet → Character → Choose Image…
- Menu bar / system tray controls, white or dark theme
- Three pen widths and eraser sizes (right-click the pen or eraser)
- No account, ads or tracking; it sends nothing anywhere (the menu can open the privacy policy and license pages in your browser)

## Get MemoBuddy

Mac App Store and Microsoft Store versions are being prepared. Until they are out, build it from source (below).

Developers who want to try a Windows build before the Store version can download the `MemoBuddy-windows-installer` artifact from the latest successful [CI run](https://github.com/tinkerer0/MemoBuddy/actions/workflows/ci.yml) (GitHub sign-in required, kept for 90 days). It is an unsigned test build, so Windows SmartScreen warns about it; everyone else should wait for the Microsoft Store version, which Microsoft signs.

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

## Adding a character

1. Draw or generate the character on a plain chroma-green (`#00FF00`) background and save it in `art/characters/`.
2. Make the GIF: `python3 scripts/character-gif.py art/characters/<name>.png public/characters/<name>.gif --motion waddle` (motions: `waddle`, `float`, `bounce`, `wobble`, `orbit`, `twinkle`; needs Pillow and numpy).
3. Add a line to `BUILT_IN` in `src-tauri/src/characters.rs`. Its `id` is saved in settings, so never change it after a release.

## Release

See [docs/RELEASE.md](docs/RELEASE.md) (Mac App Store and Microsoft Store), [docs/STORE_LISTING.md](docs/STORE_LISTING.md) and [docs/PRIVACY.md](docs/PRIVACY.md).

## Data

Notes are stored as `notes.json` (format version 4, readable by the Swift MemoPet) in the app data folder, with `notes.backup.json`. Strokes may carry an optional `width`; older readers ignore it.

## Feedback

제가 이런 분야를 접한 지 얼마 안 돼서 부족한 점이 많습니다. 고칠 점이나 알려주실 내용이 있다면 issue나 PR로 남겨주시면 너무 감사하겠습니다.

I am still new to this, so there is a lot to improve. Issues and pull requests with fixes or suggestions are very welcome.

## License

MIT — see [LICENSE](LICENSE).
