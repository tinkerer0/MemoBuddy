//! Platform window control. Everything else in the app is shared.
//!
//! macOS: the character is a native non-activating NSPanel with an
//! NSImageView (public AppKit API only, so the app can ship on the Mac App
//! Store); the memo is a Tauri webview window turned into a non-activating
//! panel that can take keyboard focus without activating MemoPet.
//! Windows: both are Tauri webview windows; the character never takes focus.

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::*;

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use windows::*;
