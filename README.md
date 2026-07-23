# MemoPet

[![CI](https://github.com/tinkerer0/MemoPet/actions/workflows/ci.yml/badge.svg)](https://github.com/tinkerer0/MemoPet/actions/workflows/ci.yml)

<p align="center">
  <img src="Sources/MemoPet/Resources/default-character.gif" width="112" alt="MemoPet writing a memo" />
</p>

MemoPet is a tiny animated notebook that stays above your macOS apps.

It was built to remove a small interruption from AI-assisted work: opening a separate notes app whenever you need to capture a quick thought or sketch. Click the little GIF character to open a speech-bubble note, then get straight back to what you were doing.

> [!NOTE]
> MemoPet is currently distributed as open-source code. There is no supported one-click installer yet. Build and run it locally with the copy-and-paste commands below.

## Features

- Click the character to open a speech-bubble notebook
- Click elsewhere to save and close the memo automatically
- Type and draw together in the same note
- Add, title, choose, and delete notes from one compact notes list with inline confirmation
- Switch between pencil and circular eraser tools
- Automatic local saving, including Korean, emoji, line breaks, and drawings
- Resize the memo from its edges; its size is remembered and drawings keep their scale
- Animated GIF, PNG, JPEG, and WebP character support
- Three bundled characters: Classic, Memo Writer, and Orbiting Planet
- Drag to move; an open memo follows the character in real time
- Right-click to change the character or size, or quit MemoPet
- Floats above apps and follows you across macOS Spaces
- Menu bar controls for recovery and less-common actions
- Lightweight update notices when a newer GitHub Release is published
- Native AppKit implementation with no Electron runtime, account, or telemetry

## Requirements

- macOS 13 or later
- Xcode Command Line Tools with Swift 5.9 or later

## Build and run

Open Terminal and copy and paste:

```sh
git clone https://github.com/tinkerer0/MemoPet.git
cd MemoPet
./scripts/build-app.sh
open dist/MemoPet.app
```

These commands download the source, build a local Universal app, and open it. MemoPet then appears as a note icon in the menu bar and a character on the desktop.

If `git` or `swift` is unavailable, install Apple's command-line tools first:

```sh
xcode-select --install
```

For development, you can run it directly with Swift Package Manager:

```sh
swift run MemoPet
```

Run the tests with:

```sh
swift test
```

Create a local Universal archive for testing with:

```sh
./scripts/package-release.sh
```

## Controls

| Action | Control |
| --- | --- |
| Open or close memo | Click the character |
| Open the notes list | Click the list and note count at the top left |
| Add a blank note | Click `+` in the notes list |
| Select and title a note | Click its title in the memo list, then type |
| Draw on the current note | Toggle the pencil in the memo |
| Move between notes | Use the arrows beside the note count or select one from the memo list |
| Cut, copy, paste, or select text | Press <kbd>⌘X</kbd>, <kbd>⌘C</kbd>, <kbd>⌘V</kbd>, or <kbd>⌘A</kbd> |
| Undo text or a drawing action | Press <kbd>⌘Z</kbd> in its editing mode |
| Redo text | Press <kbd>⇧⌘Z</kbd> in text mode |
| Erase part of a drawing | Toggle the eraser, then drag over the drawing |
| Delete a note | Click its trash icon, then confirm in that note's row |
| Close memo | Click elsewhere or press Escape |
| Move character | Drag the character |
| Resize memo | Drag any memo edge or corner |
| Change character, size, check for updates, or quit | Right-click the character |
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

To check for updates, the packaged app checks while it is running and makes one small request to GitHub's public latest-release API at most once every 24 hours, plus any checks you start from **Menu Bar → More → Check for Updates…**. Normal network metadata such as your IP address is therefore visible to GitHub. Memo contents and custom character files are never included.

An update notice appears only after this repository publishes a newer numbered GitHub Release; pushing a commit alone does not trigger one. MemoPet opens the release page after you choose **View Release** and never downloads or installs an update by itself.

## Versioning

MemoPet uses semantic versions. Bug fixes increment the last number (`v0.3.1`, `v0.3.2`), compatible feature updates increment the middle number (`v0.4.0`), and major compatibility changes increment the first number (`v1.0.0`, `v2.0.0`).

## Status

MemoPet is an early open-source macOS preview. Building from source is the supported way to run it. Existing prebuilt archives are experimental, ad-hoc signed, not notarized, and may be blocked by macOS. Launch-at-login and App Sandbox enforcement are not implemented yet.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for local checks and pull request guidance. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md), without attaching real memo content.

## License

MIT
