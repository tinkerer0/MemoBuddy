# Vendored crates

## wry 0.57.0

Copied unchanged from crates.io except `src/wkwebview/mod.rs`, where every
private macOS KVC key (`allowsPictureInPictureMediaPlayback`,
`drawsBackground`, `fullScreenEnabled`) is compiled out on macOS. MemoPet uses
none of the features behind them (video picture-in-picture, transparent
webviews, full screen on macOS < 12.3). The Mac App Store rejects private API
use, and `scripts/check-private-api.sh` verifies the built binary no longer
contains those keys. `src/lib.rs` also gets `#![allow(warnings)]` so upstream
warnings do not show up in MemoPet's build output.

When Tauri moves to a newer wry, copy the new release here, re-apply the same
`#[cfg]` gates (search the diff for "MemoPet patch"), and update the version in
`src-tauri/Cargo.toml` `[patch.crates-io]`. License: MIT or Apache-2.0 (files
kept in `vendor/wry`).
