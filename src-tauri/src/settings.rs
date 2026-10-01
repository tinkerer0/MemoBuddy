//! Small preferences file (`settings.json` in the app data folder).
//! Unknown or broken values fall back to defaults instead of failing startup.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::characters::{self, Builtin};

pub const CHARACTER_SIZES: [f64; 3] = [56.0, 80.0, 112.0];
pub const DEFAULT_CHARACTER_SIZE: f64 = 80.0;
pub const DEFAULT_MEMO_SIZE: (f64, f64) = (380.0, 300.0);
pub const MIN_MEMO_SIZE: (f64, f64) = (300.0, 200.0);
pub const MAX_MEMO_SIZE: (f64, f64) = (760.0, 620.0);
/// The only names the picked character image is stored under (app.rs imports it).
pub const CUSTOM_CHARACTER_FILES: [&str; 4] = ["custom-character.gif", "custom-character.png", "custom-character.jpg", "custom-character.webp"];

/// The character on screen: the drawn Classic one, a built-in GIF
/// (`characters::BUILT_IN`), or the picked image. Saved as its id
/// ("classic", "memoWriter", "orbitingPlanet", …, "custom").
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CharacterChoice {
    Classic,
    Builtin(&'static Builtin),
    Custom,
}

impl CharacterChoice {
    pub fn id(self) -> &'static str {
        match self {
            CharacterChoice::Classic => "classic",
            CharacterChoice::Builtin(builtin) => builtin.id,
            CharacterChoice::Custom => "custom",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        match id {
            "classic" => Some(CharacterChoice::Classic),
            "custom" => Some(CharacterChoice::Custom),
            other => characters::find(other).map(CharacterChoice::Builtin),
        }
    }
}

impl Default for CharacterChoice {
    fn default() -> Self {
        CharacterChoice::Builtin(&characters::BUILT_IN[0])
    }
}

impl Serialize for CharacterChoice {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.id())
    }
}

impl<'de> Deserialize<'de> for CharacterChoice {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        // An id this version does not know (e.g. written by a newer version),
        // or a value that is not an id at all, falls back to the default
        // instead of discarding every other setting. Reading any JSON value
        // consumes arrays and objects whole.
        let value = serde_json::Value::deserialize(deserializer)?;
        Ok(value.as_str().and_then(CharacterChoice::from_id).unwrap_or_default())
    }
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
    /// The first-run tip (click to open, right-click for settings) was dismissed.
    pub tip_seen: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            character_origin: None,
            character_size: DEFAULT_CHARACTER_SIZE,
            character_choice: CharacterChoice::default(),
            theme: None,
            memo_width: DEFAULT_MEMO_SIZE.0,
            memo_height: DEFAULT_MEMO_SIZE.1,
            custom_character_file: None,
            tip_seen: false,
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
        // The app only ever writes these names; anything else (a path, "..",
        // another data file) would let a damaged or edited settings file make
        // the app read or delete a file it did not create.
        if !self.custom_character_file.as_deref().is_some_and(|name| CUSTOM_CHARACTER_FILES.contains(&name)) {
            self.custom_character_file = None;
        }
        if self.character_choice == CharacterChoice::Custom && self.custom_character_file.is_none() {
            self.character_choice = CharacterChoice::default();
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

    /// Marks the first-run tip as seen, but only once that is on disk, so a
    /// failed save leaves it showing and it can be dismissed again.
    pub fn dismiss_tip(&mut self, dir: &Path) -> std::io::Result<()> {
        let mut next = self.clone();
        next.tip_seen = true;
        next.save(dir)?;
        *self = next;
        Ok(())
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
        assert_eq!(settings.character_choice, CharacterChoice::default());
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
        // Written before the first-run tip existed: the tip still shows once.
        assert!(!settings.tip_seen);
    }

    #[test]
    fn character_ids_round_trip_and_unknown_ones_fall_back() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(Settings::path(dir.path()), br#"{"characterChoice":"orbitingPlanet","memoWidth":500.0}"#).unwrap();
        let settings = Settings::load(dir.path());
        assert_eq!(settings.character_choice.id(), "orbitingPlanet");
        settings.save(dir.path()).unwrap();
        let json = String::from_utf8(fs::read(Settings::path(dir.path())).unwrap()).unwrap();
        assert!(json.contains("\"characterChoice\": \"orbitingPlanet\""), "{json}");

        // A character from a newer version, or a value that is not an id at
        // all: default character, other settings kept.
        for value in [r#""dragon""#, "null", "17", "true", "[]", r#"{"id":"penguin"}"#] {
            let json = format!(r#"{{"characterChoice":{value},"memoWidth":500.0,"theme":"dark","tipSeen":true}}"#);
            fs::write(Settings::path(dir.path()), json).unwrap();
            let settings = Settings::load(dir.path());
            assert_eq!(settings.character_choice, CharacterChoice::default(), "{value}");
            assert_eq!((settings.memo_width, settings.theme, settings.tip_seen), (500.0, Some(Theme::Dark), true), "{value}");
        }
    }

    #[test]
    fn only_the_apps_own_image_names_are_kept() {
        let dir = tempfile::tempdir().unwrap();
        for bad in ["../outside.png", "/etc/hosts", "notes.json", "custom-character.gif/../notes.json", "custom-character.bmp", ""] {
            let json = format!(r#"{{"characterChoice":"custom","customCharacterFile":{bad:?},"memoWidth":500.0}}"#);
            fs::write(Settings::path(dir.path()), json).unwrap();
            let settings = Settings::load(dir.path());
            assert_eq!(settings.custom_character_file, None, "{bad}");
            assert_eq!(settings.character_choice, CharacterChoice::default(), "{bad}");
            assert_eq!(settings.memo_width, 500.0, "{bad}");
        }
        for good in CUSTOM_CHARACTER_FILES {
            let json = format!(r#"{{"characterChoice":"custom","customCharacterFile":{good:?}}}"#);
            fs::write(Settings::path(dir.path()), json).unwrap();
            let settings = Settings::load(dir.path());
            assert_eq!(settings.custom_character_file.as_deref(), Some(good));
            assert_eq!(settings.character_choice, CharacterChoice::Custom);
        }
    }

    #[test]
    fn tip_stays_when_it_cannot_be_saved() {
        let dir = tempfile::tempdir().unwrap();
        // A folder where the temporary file goes makes the save fail.
        fs::create_dir(dir.path().join(".settings.json.tmp")).unwrap();
        let mut settings = Settings::default();
        assert!(settings.dismiss_tip(dir.path()).is_err());
        assert!(!settings.tip_seen);
        fs::remove_dir(dir.path().join(".settings.json.tmp")).unwrap();
        settings.dismiss_tip(dir.path()).unwrap();
        assert!(settings.tip_seen);
        assert!(Settings::load(dir.path()).tip_seen);
    }

    #[test]
    fn dismissed_tip_is_remembered() {
        let dir = tempfile::tempdir().unwrap();
        let settings = Settings { tip_seen: true, ..Settings::default() };
        settings.save(dir.path()).unwrap();
        assert!(Settings::load(dir.path()).tip_seen);
        let json = String::from_utf8(fs::read(Settings::path(dir.path())).unwrap()).unwrap();
        assert!(json.contains("\"tipSeen\": true") || json.contains("\"tipSeen\":true"), "{json}");
    }
}
