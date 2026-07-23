# MemoPet

[![CI](https://github.com/tinkerer0/MemoPet/actions/workflows/ci.yml/badge.svg)](https://github.com/tinkerer0/MemoPet/actions/workflows/ci.yml)

<p align="center">
  <img src="Sources/MemoPet/Resources/default-character.gif" width="112" alt="MemoPet writing a memo" />
</p>

MemoPet is a tiny animated notebook that stays above your macOS apps.

It was built to remove a small interruption from AI-assisted work: opening a separate notes app whenever you need to capture a quick thought or sketch. Click the little GIF character to open a speech-bubble note, then get straight back to what you were doing.

## Features

- Click the character to open a speech-bubble notebook
- Type and draw together in the same note
- Add blank notes with one click and switch drawing mode with the pencil
- Move between notes with compact previous and next controls
- Automatic local saving, including Korean, emoji, line breaks, and drawings
- Resize the memo from its edges; its size is remembered and drawings keep their scale
- Animated GIF, PNG, JPEG, and WebP character support
- Three bundled characters: Classic, Memo Writer, and Orbiting Planet
- Drag to move; an open memo follows the character in real time
- Right-click to choose Small, Medium, or Large
- Floats above apps and follows you across macOS Spaces
- Menu bar controls for recovery and less-common actions
- Lightweight update notices when a newer GitHub Release is published
- Native AppKit implementation with no Electron runtime, account, or telemetry

## Requirements

- macOS 13 or later

## Install

1. Download `MemoPet.zip` from the [latest release](https://github.com/tinkerer0/MemoPet/releases/latest).
2. Unzip it and move `MemoPet.app` to your Applications folder.
3. Open MemoPet. Its note icon appears in the menu bar, and the character appears on the desktop.

The release is a Universal app for both Apple Silicon and Intel Macs. MemoPet is not notarized yet, so macOS may block the first launch. After trying to open it once, go to **System Settings → Privacy & Security** and click **Open Anyway** only if you trust this repository and release.

## Build from source

Install Xcode Command Line Tools with Swift 5.9 or later, then run:

```bash
git clone https://github.com/tinkerer0/MemoPet.git
cd MemoPet
./scripts/build-app.sh
open dist/MemoPet.app
```

For development, you can run it directly with Swift Package Manager:

```bash
swift run MemoPet
```

Run the tests with:

```bash
swift test
```

Create the clean Universal release archive with:

```bash
./scripts/package-release.sh
```

## Controls

| Action | Control |
| --- | --- |
| Open or close memo | Click the character |
| Add a blank note | Click `+` in the memo |
| Draw on the current note | Toggle the pencil in the memo |
| Move between notes | Click the left or right arrow |
| Undo a drawing stroke | Press <kbd>⌘Z</kbd> |
| Clear the current drawing | Click the eraser in the memo |
| Delete the current note | Use **Menu Bar → More → Delete Current Note…** |
| Close memo | Click `×` or press Escape |
| Move character | Drag the character |
| Resize memo | Drag any memo edge or corner |
| Change character or size | Right-click the character |
| Updates, recovery, and extra actions | Use the menu bar icon |

Notes and custom characters are stored locally in:

```text
~/Library/Application Support/MemoPet/
```

Existing `note.txt` content is automatically carried into the first text note. The original file is left in place.

MemoPet periodically keeps a recent valid `notes.json` as `notes.backup.json`. If the main file is damaged, it restores that backup. If no valid backup exists, the damaged file is preserved as `notes-corrupt-….json` before a blank notebook is created.

The bundled mascot is part of this repository. You are responsible for the rights to any custom image you choose to use.

## Privacy and updates

MemoPet stores notes, custom characters, and preferences locally. The data directory is restricted to your macOS user, but its contents are not encrypted; software running as the same user can still read them. MemoPet has no account, analytics, advertising, or telemetry.

To check for updates, the packaged app makes one small request to GitHub's public latest-release API at most once every 24 hours, plus any checks you start from **Menu Bar → More → Check for Updates…**. Normal network metadata such as your IP address is therefore visible to GitHub. Memo contents and custom character files are never included.

An update notice appears only after this repository publishes a newer numbered GitHub Release; pushing a commit alone does not trigger one. MemoPet opens the release page after you choose **View Release** and never downloads or installs an update by itself.

## Versioning

MemoPet uses semantic versions. Bug fixes increment the last number (`v0.3.1`, `v0.3.2`), compatible feature updates increment the middle number (`v0.4.0`), and major compatibility changes increment the first number (`v1.0.0`, `v2.0.0`).

## Status

MemoPet is an early macOS preview. The downloadable app is ad-hoc signed, not notarized, and not App Sandbox-enforced yet. Launch-at-login is not implemented yet.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for local checks and pull request guidance. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md), without attaching real memo content.

## License

MIT
