# MemoPet

<p align="center">
  <img src="Sources/MemoPet/Resources/default-character.gif" width="112" alt="MemoPet writing a memo" />
</p>

MemoPet is a tiny animated scratchpad that stays above your macOS apps.

It was built to remove a small interruption from AI-assisted work: opening a separate notes app whenever you need to capture a quick thought. Click the little GIF character to open a speech-bubble memo, then get straight back to what you were doing.

## Features

- Click the character to open a speech-bubble scratchpad
- Automatic local saving, including Korean, emoji, and line breaks
- Animated GIF, PNG, JPEG, and WebP character support
- Three bundled characters: Classic, Memo Writer, and Orbiting Planet
- Drag to move; right-click to choose Small, Medium, or Large
- Floats above apps and follows you across macOS Spaces
- Menu bar controls for recovery and less-common actions
- Native AppKit implementation with no Electron runtime, account, network access, or telemetry

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

## Controls

| Action | Control |
| --- | --- |
| Open or close memo | Click the character |
| Move character | Drag the character |
| Change character or size | Right-click the character |
| Close memo | Press Escape |
| Recovery and extra actions | Use the menu bar icon |

Notes and custom characters are stored locally in:

```text
~/Library/Application Support/MemoPet/
```

The bundled mascot is part of this repository. You are responsible for the rights to any custom image you choose to use.

## Status

MemoPet is an early macOS preview. The app is not notarized yet, and launch-at-login is not implemented yet.

## License

MIT
