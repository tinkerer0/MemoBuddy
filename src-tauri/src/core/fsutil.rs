//! Small filesystem helpers shared by `store.rs` and `mirror.rs`. Not part of
//! the coordinator's contract surface (not `pub` outside `core`); pulled out
//! only to avoid duplicating the atomic-write and unix-permission logic.

use std::fs;
use std::io;
use std::path::Path;

/// Atomic write: write to a temp file in the *same directory* as `path`,
/// then rename over the destination. On POSIX, rename within one filesystem
/// is atomic, matching Swift's `Data.write(options: [.atomic])`.
pub(crate) fn write_atomic(path: &Path, data: &[u8]) -> io::Result<()> {
    let dir = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let file_name = path.file_name().and_then(|n| n.to_str()).unwrap_or("tmp");
    let tmp_path = dir.join(format!(".{file_name}.tmp-{}", uuid::Uuid::new_v4()));

    let write_result = (|| -> io::Result<()> {
        use std::io::Write;
        let mut file = fs::File::create(&tmp_path)?;
        file.write_all(data)?;
        // Flush file contents before the rename makes them the real file.
        file.sync_all()?;
        drop(file);
        fs::rename(&tmp_path, path)?;
        // Persist the rename itself (directory entry) where supported.
        #[cfg(unix)]
        if let Ok(directory) = fs::File::open(dir) {
            let _ = directory.sync_all();
        }
        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }
    write_result
}

#[cfg(unix)]
pub(crate) fn set_permissions(path: &Path, mode: u32) -> io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
pub(crate) fn set_permissions(_path: &Path, _mode: u32) -> io::Result<()> {
    Ok(())
}

/// 0700 on unix; no-op on other platforms (see module doc).
pub(crate) fn secure_dir(path: &Path) -> io::Result<()> {
    set_permissions(path, 0o700)
}

/// 0600 on unix; no-op on other platforms (see module doc).
pub(crate) fn secure_file(path: &Path) -> io::Result<()> {
    set_permissions(path, 0o600)
}
