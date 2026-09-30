//! Small preferences file (`settings.json` in the app data folder).
//! Unknown or broken values fall back to defaults instead of failing startup.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

pub const CHARACTER_SIZES: [f64; 3] = [56.0, 80.0, 112.0];
pub const DEFAULT_CHARACTER_SIZE: f64 = 80.0;
pub const DEFAULT_MEMO_SIZE: (f64, f64) = (380.0, 300.0);
pub const MIN_MEMO_SIZE: (f64, f64) = (300.0, 200.0);
pub const MAX_MEMO_SIZE: (f64, f64) = (760.0, 620.0);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CharacterChoice {
    Classic,
    MemoWriter,
    OrbitingPlanet,
    Custom,
}

/// The memo and character colors: white or dark.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Theme {
    Light,
    Dark,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    /// Top-left of the character window in logical points (y grows down).
    pub character_origin: Option<(f64, f64)>,
    pub character_size: f64,
    pub character_choice: CharacterChoice,
    /// `None` until the first launch picks one from the system appearance.
    pub theme: Option<Theme>,
    pub memo_width: f64,
    pub memo_height: f64,
    /// File name of the imported custom character inside the data folder.
    pub custom_character_file: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            character_origin: None,
            character_size: DEFAULT_CHARACTER_SIZE,
            character_choice: CharacterChoice::MemoWriter,
            theme: None,
            memo_width: DEFAULT_MEMO_SIZE.0,
            memo_height: DEFAULT_MEMO_SIZE.1,
            custom_character_file: None,
        }
    }
}

impl Settings {
    pub fn path(dir: &Path) -> PathBuf {
        dir.join("settings.json")
    }

    pub fn load(dir: &Path) -> Self {
        let mut settings: Settings = fs::read(Self::path(dir))
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        settings.sanitize();
        settings
    }

    pub fn sanitize(&mut self) {
        if !CHARACTER_SIZES.contains(&self.character_size) {
            self.character_size = DEFAULT_CHARACTER_SIZE;
        }
        let finite = |value: f64, fallback: f64| if value.is_finite() { value } else { fallback };
        self.memo_width = finite(self.memo_width, DEFAULT_MEMO_SIZE.0).clamp(MIN_MEMO_SIZE.0, MAX_MEMO_SIZE.0);
        self.memo_height = finite(self.memo_height, DEFAULT_MEMO_SIZE.1).clamp(MIN_MEMO_SIZE.1, MAX_MEMO_SIZE.1);
        if let Some((x, y)) = self.character_origin {
            if !x.is_finite() || !y.is_finite() {
                self.character_origin = None;
            }
        }
        if self.character_choice == CharacterChoice::Custom && self.custom_character_file.is_none() {
            self.character_choice = CharacterChoice::MemoWriter;
        }
    }

    /// Atomic write with owner-only permissions on unix.
    pub fn save(&self, dir: &Path) -> std::io::Result<()> {
        let bytes = serde_json::to_vec_pretty(self)?;
        let target = Self::path(dir);
        let temporary = dir.join(".settings.json.tmp");
        {
            let mut file = fs::File::create(&temporary)?;
            file.write_all(&bytes)?;
            file.sync_all()?;
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&temporary, fs::Permissions::from_mode(0o600))?;
        }
        fs::rename(&temporary, &target)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn broken_values_fall_back_to_defaults() {
        let mut settings = Settings {
            character_size: 13.0,
            memo_width: f64::NAN,
            memo_height: 10_000.0,
            character_origin: Some((f64::INFINITY, 2.0)),
            character_choice: CharacterChoice::Custom,
            custom_character_file: None,
            ..Settings::default()
        };
        settings.sanitize();
        assert_eq!(settings.character_size, DEFAULT_CHARACTER_SIZE);
        assert_eq!(settings.memo_width, DEFAULT_MEMO_SIZE.0);
        assert_eq!(settings.memo_height, MAX_MEMO_SIZE.1);
        assert_eq!(settings.character_origin, None);
        assert_eq!(settings.character_choice, CharacterChoice::MemoWriter);
    }

    #[test]
    fn save_then_load_round_trips() {
        let dir = tempfile::tempdir().unwrap();
        let settings = Settings {
            character_origin: Some((10.0, 20.0)),
            character_size: 56.0,
            character_choice: CharacterChoice::Classic,
            theme: Some(Theme::Dark),
            ..Settings::default()
        };
        settings.save(dir.path()).unwrap();
        assert_eq!(Settings::load(dir.path()), settings);
    }

    #[test]
    fn missing_or_corrupt_file_gives_defaults() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(Settings::load(dir.path()), Settings::default());
        fs::write(Settings::path(dir.path()), b"{not json").unwrap();
        assert_eq!(Settings::load(dir.path()), Settings::default());
    }
}

#[cfg(test)]
mod compatibility_tests {
    use super::*;

    // Settings written by the earlier build (with mirror/visibility fields)
    // still load; unknown keys are ignored.
    #[test]
    fn old_settings_with_removed_fields_still_load() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            Settings::path(dir.path()),
            br#"{"characterSize":112.0,"characterChoice":"classic","characterVisible":false,"mirrorFolder":"x","memoWidth":490.0,"memoHeight":300.0}"#,
        )
        .unwrap();
        let settings = Settings::load(dir.path());
        assert_eq!(settings.character_size, 112.0);
        assert_eq!(settings.character_choice, CharacterChoice::Classic);
        assert_eq!(settings.memo_width, 490.0);
        assert_eq!(settings.theme, None);
    }
}
