//! CONTRACT: `MemoNotebookStore` public API below. Behaviour must match the
//! Swift `MemoNotebookStore` (atomic writes, owner-only permissions, 30 s
//! backup refresh, damaged-file preservation, newer-version refusal, legacy
//! `note.txt` carry-over) plus the read-only import.
//!
//! Clock: the Swift store gates the backup refresh with wall-clock
//! `Date()`. The coordinator's contract for this port asks for a monotonic,
//! test-injectable clock instead (see `with_clock`), so `new` uses a
//! monotonic clock sourced from `Instant` and tests can inject their own.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::Instant;

use uuid::Uuid;

use super::fsutil;
use super::model::{MemoNote, MemoNotebook, CURRENT_VERSION};

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("These notes were created by a newer MemoBuddy data format (version {0}).")]
    UnsupportedVersion(i64),
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Json(#[from] serde_json::Error),
    #[error("No MemoBuddy notes were found in that folder.")]
    NothingToImport,
    #[error("The drawing contains an invalid point.")]
    InvalidDrawing,
}

/// Result of `import_from_dir`.
#[derive(Debug, Clone, PartialEq)]
pub struct ImportReport {
    pub imported_notes: usize,
    /// Which source file the notes came from, e.g. "notes.json".
    pub source_file: String,
}

const BACKUP_INTERVAL_SECS: f64 = 30.0;

type ClockFn = Box<dyn Fn() -> f64 + Send + Sync>;

pub struct MemoNotebookStore {
    pub notebook_path: PathBuf,
    pub backup_path: PathBuf,
    pub legacy_note_path: PathBuf,
    last_backup: Option<f64>,
    recovery_notice: Option<String>,
    clock: ClockFn,
}

fn monotonic_now() -> f64 {
    static START: OnceLock<Instant> = OnceLock::new();
    let start = START.get_or_init(Instant::now);
    start.elapsed().as_secs_f64()
}

/// Parses+validates a notebook the way Swift's `decodeNotebook(from:)` does:
/// malformed JSON surfaces as `StoreError::Json` (treated as "damaged" by
/// callers), a `version` newer than we understand surfaces as
/// `StoreError::UnsupportedVersion` (never treated as damaged), and anything
/// else is normalized (`sanitizeContent: true`) before being handed back.
fn decode_notebook(data: &[u8]) -> Result<MemoNotebook, StoreError> {
    // Read only the version first: a newer file may contain values this
    // version cannot decode, and it must be refused, never treated as damaged.
    #[derive(serde::Deserialize)]
    struct VersionHeader {
        version: i64,
    }
    if let Ok(header) = serde_json::from_slice::<VersionHeader>(data) {
        if header.version > CURRENT_VERSION {
            return Err(StoreError::UnsupportedVersion(header.version));
        }
    }
    let mut notebook: MemoNotebook = serde_json::from_slice(data)?;
    if notebook.version > CURRENT_VERSION {
        return Err(StoreError::UnsupportedVersion(notebook.version));
    }
    notebook.normalize(true);
    Ok(notebook)
}

fn encode_notebook(notebook: &MemoNotebook) -> Result<Vec<u8>, StoreError> {
    // Round-trip through `Value` so keys serialize in sorted order (default
    // `serde_json::Map` is a `BTreeMap` since this crate does not enable the
    // `preserve_order` feature), mirroring Swift's `JSONEncoder.sortedKeys`.
    let value = serde_json::to_value(notebook)?;
    Ok(serde_json::to_vec(&value)?)
}

fn file_name_of(path: &Path) -> String {
    path.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or_default()
        .to_string()
}

impl MemoNotebookStore {
    /// Creates `dir` if needed (owner-only permissions on unix).
    pub fn new(dir: &Path) -> Result<Self, StoreError> {
        Self::with_clock(dir, monotonic_now)
    }

    /// Test seam (extension beyond the coordinator's stub list): same as
    /// `new`, but with an injectable monotonic clock (seconds) so tests can
    /// exercise the 30 s backup-refresh window without sleeping.
    pub fn with_clock(
        dir: &Path,
        clock: impl Fn() -> f64 + Send + Sync + 'static,
    ) -> Result<Self, StoreError> {
        fs::create_dir_all(dir)?;
        fsutil::secure_dir(dir)?;

        let notebook_path = dir.join("notes.json");
        let backup_path = dir.join("notes.backup.json");
        let legacy_note_path = dir.join("note.txt");

        for path in [&notebook_path, &backup_path, &legacy_note_path] {
            if path.exists() {
                fsutil::secure_file(path)?;
            }
        }

        Ok(Self {
            notebook_path,
            backup_path,
            legacy_note_path,
            last_backup: None,
            recovery_notice: None,
            clock: Box::new(clock),
        })
    }

    pub fn load(&mut self) -> Result<MemoNotebook, StoreError> {
        self.recovery_notice = None;

        if self.notebook_path.exists() {
            let data = fs::read(&self.notebook_path)?;
            return match decode_notebook(&data) {
                Ok(notebook) => Ok(notebook),
                Err(StoreError::UnsupportedVersion(version)) => {
                    Err(StoreError::UnsupportedVersion(version))
                }
                Err(_) => self.recover_from_damaged_notebook(),
            };
        }

        if !self.legacy_note_path.exists() {
            return Ok(MemoNotebook::new());
        }

        let legacy_text = fs::read_to_string(&self.legacy_note_path)?;
        let mut note = MemoNote::new();
        note.text = legacy_text;
        let id = note.id;
        let notebook = MemoNotebook {
            version: CURRENT_VERSION,
            notes: vec![note],
            selected_note_id: id,
        };
        self.save(&notebook)?;
        Ok(notebook)
    }

    pub fn save(&mut self, notebook: &MemoNotebook) -> Result<(), StoreError> {
        // JSON has no NaN/Infinity: they would be written as null and make the
        // file unreadable, so refuse them like Swift's encoder does.
        let finite = notebook
            .notes
            .iter()
            .flat_map(|note| &note.strokes)
            .all(|stroke| stroke.width.is_none_or(f64::is_finite) && stroke.points.iter().all(|point| point.x.is_finite() && point.y.is_finite()));
        if !finite {
            return Err(StoreError::InvalidDrawing);
        }
        let mut normalized = notebook.clone();
        normalized.normalize(false);
        let data = encode_notebook(&normalized)?;

        let now = (self.clock)();
        let should_refresh_backup = match self.last_backup {
            Some(last) => {
                let elapsed = now - last;
                elapsed < 0.0 || elapsed >= BACKUP_INTERVAL_SECS
            }
            None => true,
        };

        if should_refresh_backup && self.notebook_path.exists() {
            if let Ok(existing_data) = fs::read(&self.notebook_path) {
                if decode_notebook(&existing_data).is_ok() {
                    fsutil::write_atomic(&self.backup_path, &existing_data)?;
                    fsutil::secure_file(&self.backup_path)?;
                    self.last_backup = Some(now);
                }
            }
        }

        fsutil::write_atomic(&self.notebook_path, &data)?;
        fsutil::secure_file(&self.notebook_path)?;
        Ok(())
    }

    /// Set by `load` when a damaged file was preserved or a backup restored.
    pub fn recovery_notice(&self) -> Option<&str> {
        self.recovery_notice.as_deref()
    }

    /// Reads another MemoPet data folder (e.g. the Swift app's
    /// `~/Library/Application Support/MemoPet`) WITHOUT writing to it, and
    /// appends its non-empty notes to `into` as new notes (fresh ids on
    /// collision). Prefers a valid notes.json, then notes.backup.json, then
    /// note.txt. Does not save; the caller saves `into`.
    ///
    /// Design decision beyond the contract's prose: a newer-version
    /// candidate file is a hard `UnsupportedVersion` error (no fallback to
    /// the next candidate), mirroring `load()`'s own single-file semantics
    /// (a newer version is never treated as "just try something else").
    pub fn import_from_dir(
        source_dir: &Path,
        into: &mut MemoNotebook,
    ) -> Result<ImportReport, StoreError> {
        let notebook_path = source_dir.join("notes.json");
        let backup_path = source_dir.join("notes.backup.json");
        let legacy_path = source_dir.join("note.txt");

        if notebook_path.exists() {
            let data = fs::read(&notebook_path)?;
            match decode_notebook(&data) {
                Ok(notebook) => return Self::merge_import(into, notebook.notes, "notes.json"),
                Err(StoreError::UnsupportedVersion(version)) => {
                    return Err(StoreError::UnsupportedVersion(version))
                }
                Err(_) => {}
            }
        }

        if backup_path.exists() {
            let data = fs::read(&backup_path)?;
            match decode_notebook(&data) {
                Ok(notebook) => {
                    return Self::merge_import(into, notebook.notes, "notes.backup.json")
                }
                Err(StoreError::UnsupportedVersion(version)) => {
                    return Err(StoreError::UnsupportedVersion(version))
                }
                Err(_) => {}
            }
        }

        if legacy_path.exists() {
            let text = fs::read_to_string(&legacy_path)?;
            if !text.is_empty() {
                let mut note = MemoNote::new();
                note.text = text;
                return Self::merge_import(into, vec![note], "note.txt");
            }
        }

        Err(StoreError::NothingToImport)
    }

    fn merge_import(
        into: &mut MemoNotebook,
        source_notes: Vec<MemoNote>,
        source_file: &str,
    ) -> Result<ImportReport, StoreError> {
        let mut existing_ids: HashSet<Uuid> = into.notes.iter().map(|note| note.id).collect();
        let mut imported = 0usize;

        for mut note in source_notes {
            if note.is_empty() {
                continue;
            }
            if existing_ids.contains(&note.id) {
                note.id = Uuid::new_v4();
            }
            existing_ids.insert(note.id);
            into.notes.push(note);
            imported += 1;
        }

        if imported == 0 {
            return Err(StoreError::NothingToImport);
        }

        Ok(ImportReport {
            imported_notes: imported,
            source_file: source_file.to_string(),
        })
    }

    fn recover_from_damaged_notebook(&mut self) -> Result<MemoNotebook, StoreError> {
        let mut preserved_backup_name: Option<String> = None;

        if self.backup_path.exists() {
            let backup_data = fs::read(&self.backup_path)?;
            match decode_notebook(&backup_data) {
                Ok(recovered) => {
                    let preserved =
                        self.preserve_damaged_file(&self.notebook_path.clone(), "notes-corrupt")?;
                    self.save(&recovered)?;
                    self.recovery_notice = Some(format!(
                        "The notes file was damaged, so MemoBuddy preserved it as {} and restored a recent backup.",
                        file_name_of(&preserved)
                    ));
                    return Ok(recovered);
                }
                Err(StoreError::UnsupportedVersion(version)) => {
                    return Err(StoreError::UnsupportedVersion(version))
                }
                Err(_) => {
                    let preserved = self
                        .preserve_damaged_file(&self.backup_path.clone(), "notes-backup-corrupt")?;
                    preserved_backup_name = Some(file_name_of(&preserved));
                }
            }
        }

        let preserved_notebook =
            self.preserve_damaged_file(&self.notebook_path.clone(), "notes-corrupt")?;
        let blank = MemoNotebook::new();
        self.save(&blank)?;

        let mut names = vec![file_name_of(&preserved_notebook)];
        if let Some(backup_name) = &preserved_backup_name {
            names.push(backup_name.clone());
        }
        let preserved_names = names.join(" and ");
        self.recovery_notice = Some(if preserved_backup_name.is_none() {
            format!("The notes file was damaged. MemoBuddy started a blank notebook and preserved it as {preserved_names}.")
        } else {
            format!("The notes files were damaged. MemoBuddy started a blank notebook and preserved them as {preserved_names}.")
        });
        Ok(blank)
    }

    fn preserve_damaged_file(
        &self,
        source: &Path,
        name_prefix: &str,
    ) -> Result<PathBuf, StoreError> {
        let dir = source
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        let preserved = dir.join(format!(
            "{name_prefix}-{}.json",
            super::model::uuid_upper_string(Uuid::new_v4())
        ));
        fs::copy(source, &preserved)?;
        fsutil::secure_file(&preserved)?;
        Ok(preserved)
    }
}

#[cfg(test)]
mod review_regression_tests {
    use super::super::model::{MemoNote, MemoPoint, MemoStroke};
    use super::*;

    // Review finding: a newer file with values this version cannot
    // decode must be refused and left byte-for-byte unchanged.
    #[test]
    fn newer_version_with_unknown_values_is_refused_and_untouched() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("notes.json");
        let future = br#"{"version":999,"selectedNoteID":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","notes":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","text":"x","strokes":[],"drawingCoordinateSpace":"futureSpace"}]}"#;
        fs::write(&path, future).unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        assert!(matches!(store.load(), Err(StoreError::UnsupportedVersion(999))));
        assert_eq!(fs::read(&path).unwrap(), future.to_vec());
        let names: Vec<String> = fs::read_dir(dir.path()).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        assert!(names.iter().all(|name| !name.contains("corrupt")), "{names:?}");
    }

    // Review finding: non-finite points would be written as null.
    #[test]
    fn non_finite_points_are_refused_and_file_is_unchanged() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        let good = MemoNotebook::new();
        store.save(&good).unwrap();
        let before = fs::read(dir.path().join("notes.json")).unwrap();
        let mut bad = good.clone();
        bad.notes[0] = MemoNote {
            text: "keep me".into(),
            strokes: vec![MemoStroke { width: None, points: vec![MemoPoint { x: f64::INFINITY, y: 1.0 }] }],
            ..bad.notes[0].clone()
        };
        assert!(matches!(store.save(&bad), Err(StoreError::InvalidDrawing)));
        assert_eq!(fs::read(dir.path().join("notes.json")).unwrap(), before);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    fn permissions_mode(path: &Path) -> u32 {
        use std::os::unix::fs::PermissionsExt;
        fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    fn preserved_files(dir: &Path, prefix: &str) -> Vec<PathBuf> {
        fs::read_dir(dir)
            .unwrap()
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|n| n.to_str())
                    .is_some_and(|n| n.starts_with(prefix))
            })
            .collect()
    }

    // Swift: testMissingNotebookLoadsOneBlankNote
    #[test]
    fn missing_notebook_loads_one_blank_note() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();

        let notebook = store.load().unwrap();

        assert_eq!(notebook.notes.len(), 1);
        assert_eq!(notebook.selected_note().text, "");
        assert!(notebook.selected_note().strokes.is_empty());
    }

    // Swift: testSaveAndLoadPreservesTextDrawingAndSelection
    #[test]
    fn save_and_load_preserves_text_drawing_and_selection() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        let text_note = MemoNote {
            title: Some("오늘 할 일".to_string()),
            text: "에이전트 결과 확인 🐈".to_string(),
            ..MemoNote::new()
        };
        let hybrid_note = MemoNote {
            text: "Circle this".to_string(),
            strokes: vec![super::super::model::MemoStroke {
                width: None,
                points: vec![
                    super::super::model::MemoPoint { x: 0.1, y: 0.2 },
                    super::super::model::MemoPoint { x: 0.8, y: 0.7 },
                ],
            }],
            ..MemoNote::new()
        };
        let hybrid_id = hybrid_note.id;
        let notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: hybrid_id,
            notes: vec![text_note, hybrid_note],
        };

        store.save(&notebook).unwrap();
        let loaded = store.load().unwrap();

        assert_eq!(loaded, notebook);
        assert!(store.notebook_path.exists());
        #[cfg(unix)]
        {
            assert_eq!(permissions_mode(dir.path()), 0o700);
            assert_eq!(permissions_mode(&store.notebook_path), 0o600);
        }
    }

    // Swift: testLegacyTextMigratesWithoutRemovingOriginalFile (simplified:
    // writes note.txt directly instead of going through Swift's separate
    // `ScratchpadStore`, which has no counterpart in this Rust contract).
    #[test]
    fn legacy_text_migrates_without_removing_original_file() {
        let dir = tempfile::tempdir().unwrap();
        let text = "Keep this existing note\n두 번째 줄";
        fs::write(dir.path().join("note.txt"), text).unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();

        let notebook = store.load().unwrap();

        assert_eq!(notebook.notes.len(), 1);
        assert_eq!(notebook.selected_note().text, text);
        assert!(store.notebook_path.exists());
        assert!(store.legacy_note_path.exists());
    }

    // Swift: testVersionOneNotebookMigratesTextAndDrawingIntoHybridNotes
    #[test]
    fn version_one_notebook_migrates_text_and_drawing_into_hybrid_notes() {
        let dir = tempfile::tempdir().unwrap();
        let store = MemoNotebookStore::new(dir.path()).unwrap();
        let text_id = Uuid::new_v4();
        let drawing_id = Uuid::new_v4();
        let json = format!(
            r#"{{
              "version": 1,
              "selectedNoteID": "{drawing_id}",
              "notes": [
                {{"id": "{text_id}", "kind": "text", "text": "Keep me", "strokes": []}},
                {{"id": "{drawing_id}", "kind": "drawing", "text": "", "strokes": [{{"points": [{{"x": 0.25, "y": 0.75}}]}}]}}
              ]
            }}"#
        );
        fs::write(&store.notebook_path, json).unwrap();
        let mut store = store;

        let notebook = store.load().unwrap();

        assert_eq!(notebook.version, CURRENT_VERSION);
        assert_eq!(
            notebook.notes.iter().map(|n| n.id).collect::<Vec<_>>(),
            vec![text_id, drawing_id]
        );
        assert_eq!(notebook.notes[0].text, "Keep me");
        assert_eq!(notebook.notes[0].title, None);
        assert_eq!(notebook.notes[1].strokes.len(), 1);
        assert_eq!(notebook.notes[1].drawing_coordinate_space, None);
        assert_eq!(notebook.selected_note_id, drawing_id);
    }

    // Swift: testDamagedNotebookRestoresLatestValidBackup
    #[test]
    fn damaged_notebook_restores_latest_valid_backup() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        let backed_up = MemoNotebook {
            notes: vec![MemoNote {
                text: "Backed up".to_string(),
                ..MemoNote::new()
            }],
            ..MemoNotebook::new()
        };
        let backed_up = MemoNotebook {
            selected_note_id: backed_up.notes[0].id,
            ..backed_up
        };
        let newer = MemoNotebook {
            notes: vec![MemoNote {
                text: "Newer".to_string(),
                ..MemoNote::new()
            }],
            ..MemoNotebook::new()
        };
        let newer = MemoNotebook {
            selected_note_id: newer.notes[0].id,
            ..newer
        };
        store.save(&backed_up).unwrap();
        store.save(&newer).unwrap();
        let damaged_data = b"{truncated".to_vec();
        fs::write(&store.notebook_path, &damaged_data).unwrap();

        let recovered = store.load().unwrap();
        let preserved = preserved_files(dir.path(), "notes-corrupt-");

        assert_eq!(recovered.selected_note().text, "Backed up");
        assert_eq!(preserved.len(), 1);
        assert_eq!(fs::read(&preserved[0]).unwrap(), damaged_data);
        assert!(store.recovery_notice().is_some());
        assert_eq!(store.load().unwrap().selected_note().text, "Backed up");
    }

    // Swift: testDamagedNotebookWithoutBackupIsPreservedBeforeStartingBlank
    #[test]
    fn damaged_notebook_without_backup_is_preserved_before_starting_blank() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        let damaged_data = b"{not json".to_vec();
        fs::write(&store.notebook_path, &damaged_data).unwrap();

        let recovered = store.load().unwrap();
        let preserved = preserved_files(dir.path(), "notes-corrupt-");

        let expected_note = MemoNote {
            id: recovered.notes[0].id,
            ..MemoNote::new()
        };
        assert_eq!(recovered.notes, vec![expected_note]);
        assert_eq!(preserved.len(), 1);
        assert_eq!(fs::read(&preserved[0]).unwrap(), damaged_data);
        assert!(store.recovery_notice().is_some());
    }

    // Swift: testDamagedNotebookAndBackupRemainPreservedAfterNextSave
    #[test]
    fn damaged_notebook_and_backup_remain_preserved_after_next_save() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        let damaged_notebook_data = b"{broken notebook".to_vec();
        let damaged_backup_data = b"{broken backup".to_vec();
        fs::write(&store.notebook_path, &damaged_notebook_data).unwrap();
        fs::write(&store.backup_path, &damaged_backup_data).unwrap();

        let recovered = store.load().unwrap();
        store.save(&recovered).unwrap();

        let preserved_notebooks = preserved_files(dir.path(), "notes-corrupt-");
        let preserved_backups = preserved_files(dir.path(), "notes-backup-corrupt-");

        assert_eq!(preserved_notebooks.len(), 1);
        assert_eq!(preserved_backups.len(), 1);
        assert_eq!(
            fs::read(&preserved_notebooks[0]).unwrap(),
            damaged_notebook_data
        );
        assert_eq!(
            fs::read(&preserved_backups[0]).unwrap(),
            damaged_backup_data
        );
        assert!(store
            .recovery_notice()
            .unwrap()
            .contains("notes-backup-corrupt-"));
    }

    // Swift: testNewerNotebookVersionIsNotOverwritten
    #[test]
    fn newer_notebook_version_is_not_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        let note_id = Uuid::new_v4();
        let json = format!(
            r#"{{"version": 999, "selectedNoteID": "{note_id}", "notes": [{{"id": "{note_id}", "text": "Future", "strokes": []}}]}}"#
        );
        fs::write(&store.notebook_path, &json).unwrap();

        let result = store.load();

        assert!(matches!(result, Err(StoreError::UnsupportedVersion(999))));
        assert_eq!(fs::read(&store.notebook_path).unwrap(), json.into_bytes());
    }

    // Swift: testLongUnicodeTextAndManyDrawingPointsRoundTrip
    #[test]
    fn long_unicode_text_and_many_drawing_points_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        let text = "긴 메모 line 📝\n".repeat(10_000);
        let strokes: Vec<super::super::model::MemoStroke> = (0..50)
            .map(|stroke_index| super::super::model::MemoStroke {
                width: None,
                points: (0..100)
                    .map(|point_index| super::super::model::MemoPoint {
                        x: point_index as f64 / 99.0,
                        y: stroke_index as f64 / 49.0,
                    })
                    .collect(),
            })
            .collect();
        let note = MemoNote {
            text,
            strokes,
            ..MemoNote::new()
        };
        let note_id = note.id;
        let notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: note_id,
            notes: vec![note],
        };

        store.save(&notebook).unwrap();
        let loaded = store.load().unwrap();

        assert_eq!(loaded, notebook);
        assert!(fs::read(&store.notebook_path).unwrap().len() > 100_000);
    }

    // New: exercises the 30s backup-refresh gate directly via the
    // coordinator-requested injectable monotonic clock (none of the ported
    // Swift tests wait out or control the interval).
    #[test]
    fn backup_refreshes_at_most_every_thirty_seconds() {
        let dir = tempfile::tempdir().unwrap();
        let clock_seconds = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
        let clock_for_store = clock_seconds.clone();
        let mut store = MemoNotebookStore::with_clock(dir.path(), move || {
            f64::from_bits(clock_for_store.load(std::sync::atomic::Ordering::SeqCst))
        })
        .unwrap();
        let set_now = |seconds: f64| {
            clock_seconds.store(seconds.to_bits(), std::sync::atomic::Ordering::SeqCst)
        };

        set_now(0.0);
        let v1 = MemoNotebook {
            notes: vec![MemoNote {
                text: "v1".to_string(),
                ..MemoNote::new()
            }],
            ..MemoNotebook::new()
        };
        let v1 = MemoNotebook {
            selected_note_id: v1.notes[0].id,
            ..v1
        };
        store.save(&v1).unwrap(); // no prior notebook.json on disk: nothing to back up yet
        assert!(!store.backup_path.exists());

        set_now(5.0);
        let v2 = MemoNotebook {
            notes: vec![MemoNote {
                text: "v2".to_string(),
                ..MemoNote::new()
            }],
            ..MemoNotebook::new()
        };
        let v2 = MemoNotebook {
            selected_note_id: v2.notes[0].id,
            ..v2
        };
        store.save(&v2).unwrap(); // first save with an existing valid notebook.json: always backs up
        let backup_after_first = fs::read_to_string(&store.backup_path).unwrap();
        assert!(backup_after_first.contains("\"v1\""));

        set_now(10.0); // only 5s after the backup at t=5: too soon to refresh again
        let v3 = MemoNotebook {
            notes: vec![MemoNote {
                text: "v3".to_string(),
                ..MemoNote::new()
            }],
            ..MemoNotebook::new()
        };
        let v3 = MemoNotebook {
            selected_note_id: v3.notes[0].id,
            ..v3
        };
        store.save(&v3).unwrap();
        let backup_after_second = fs::read_to_string(&store.backup_path).unwrap();
        assert!(
            backup_after_second.contains("\"v1\""),
            "backup must still hold v1: 30s have not elapsed"
        );

        set_now(36.0); // 31s after the backup at t=5: due for a refresh
        let v4 = MemoNotebook {
            notes: vec![MemoNote {
                text: "v4".to_string(),
                ..MemoNote::new()
            }],
            ..MemoNotebook::new()
        };
        let v4 = MemoNotebook {
            selected_note_id: v4.notes[0].id,
            ..v4
        };
        store.save(&v4).unwrap();
        let backup_after_third = fs::read_to_string(&store.backup_path).unwrap();
        assert!(
            backup_after_third.contains("\"v3\""),
            "backup must now hold v3 (the notebook.json just before this save)"
        );
    }

    // New: exercises `import_from_dir` (not present in the Swift core).
    #[test]
    fn import_from_dir_prefers_notes_json_and_never_touches_source() {
        let source = tempfile::tempdir().unwrap();
        let mut source_store = MemoNotebookStore::new(source.path()).unwrap();
        let imported_note = MemoNote {
            text: "From source".to_string(),
            ..MemoNote::new()
        };
        let source_notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: imported_note.id,
            notes: vec![imported_note],
        };
        source_store.save(&source_notebook).unwrap();

        // Snapshot the source directory (names, bytes, unix permissions).
        let before: Vec<(String, Vec<u8>, Option<u32>)> = fs::read_dir(source.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| {
                let path = e.path();
                let bytes = fs::read(&path).unwrap();
                #[cfg(unix)]
                let mode = Some(permissions_mode(&path));
                #[cfg(not(unix))]
                let mode = None;
                (e.file_name().to_string_lossy().to_string(), bytes, mode)
            })
            .collect();

        let mut into = MemoNotebook::new();
        let report = MemoNotebookStore::import_from_dir(source.path(), &mut into).unwrap();

        assert_eq!(report.source_file, "notes.json");
        assert_eq!(report.imported_notes, 1);
        assert_eq!(
            into.notes.len(),
            2,
            "the pre-existing blank note plus the imported one"
        );
        assert!(into.notes.iter().any(|n| n.text == "From source"));

        let after: Vec<(String, Vec<u8>, Option<u32>)> = fs::read_dir(source.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| {
                let path = e.path();
                let bytes = fs::read(&path).unwrap();
                #[cfg(unix)]
                let mode = Some(permissions_mode(&path));
                #[cfg(not(unix))]
                let mode = None;
                (e.file_name().to_string_lossy().to_string(), bytes, mode)
            })
            .collect();
        let mut before_sorted = before;
        let mut after_sorted = after;
        before_sorted.sort();
        after_sorted.sort();
        assert_eq!(
            before_sorted, after_sorted,
            "import_from_dir must not modify the source directory at all"
        );
    }

    #[test]
    fn import_from_dir_falls_back_to_backup_then_legacy_note() {
        let source = tempfile::tempdir().unwrap();
        // Only a backup file (no notes.json).
        let backup_note = MemoNote {
            text: "From backup".to_string(),
            ..MemoNote::new()
        };
        let backup_notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: backup_note.id,
            notes: vec![backup_note],
        };
        fs::write(
            source.path().join("notes.backup.json"),
            serde_json::to_vec(&backup_notebook).unwrap(),
        )
        .unwrap();

        let mut into = MemoNotebook::new();
        let report = MemoNotebookStore::import_from_dir(source.path(), &mut into).unwrap();
        assert_eq!(report.source_file, "notes.backup.json");
        assert!(into.notes.iter().any(|n| n.text == "From backup"));

        // Legacy note.txt only, in a fresh source dir.
        let legacy_source = tempfile::tempdir().unwrap();
        fs::write(legacy_source.path().join("note.txt"), "legacy text").unwrap();
        let mut into2 = MemoNotebook::new();
        let report2 = MemoNotebookStore::import_from_dir(legacy_source.path(), &mut into2).unwrap();
        assert_eq!(report2.source_file, "note.txt");
        assert!(into2.notes.iter().any(|n| n.text == "legacy text"));
    }

    #[test]
    fn import_from_dir_regenerates_colliding_ids_and_skips_empty_notes() {
        let source = tempfile::tempdir().unwrap();
        let mut into = MemoNotebook::new();
        let existing_id = into.notes[0].id;

        // Source has a note whose id collides with `into`'s existing note,
        // plus a blank note that must be skipped.
        let colliding = MemoNote {
            id: existing_id,
            text: "Collides".to_string(),
            ..MemoNote::new()
        };
        let blank = MemoNote::new();
        let source_notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: colliding.id,
            notes: vec![colliding, blank],
        };
        fs::write(
            source.path().join("notes.json"),
            serde_json::to_vec(&source_notebook).unwrap(),
        )
        .unwrap();

        let report = MemoNotebookStore::import_from_dir(source.path(), &mut into).unwrap();

        assert_eq!(
            report.imported_notes, 1,
            "the blank note must not be imported"
        );
        assert_eq!(into.notes.len(), 2);
        let imported = into.notes.iter().find(|n| n.text == "Collides").unwrap();
        assert_ne!(imported.id, existing_id, "colliding id must be regenerated");
    }

    #[test]
    fn import_from_dir_returns_nothing_to_import_for_an_empty_source() {
        let source = tempfile::tempdir().unwrap();
        let mut into = MemoNotebook::new();

        let result = MemoNotebookStore::import_from_dir(source.path(), &mut into);

        assert!(matches!(result, Err(StoreError::NothingToImport)));
    }

    // Compat (criterion 4a, Swift -> Rust): `fixtures/swift_sample_notebook`
    // was generated by the real Swift MemoPetCore
    // (`compat/swift-reader generate`, see compat/README notes in the task
    // report) so this proves the Rust store loads genuine Swift output:
    // uppercase UUIDs, `selectedNoteID`, sorted keys, an omitted
    // `drawingCoordinateSpace` key for a legacy note, Korean text + emoji,
    // and a titled note. Copies into a temp dir first so the checked-in
    // fixture is never chmod'd or overwritten by the store.
    #[test]
    fn loads_the_swift_generated_fixture_notebook() {
        let fixture_path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../fixtures/swift_sample_notebook/notes.json");
        let fixture_bytes = fs::read(&fixture_path)
            .unwrap_or_else(|e| panic!("read {}: {e}", fixture_path.display()));

        let dir = tempfile::tempdir().unwrap();
        let mut store = MemoNotebookStore::new(dir.path()).unwrap();
        fs::write(&store.notebook_path, &fixture_bytes).unwrap();

        let notebook = store.load().unwrap();

        assert_eq!(notebook.version, CURRENT_VERSION);
        assert_eq!(notebook.notes.len(), 4);
        assert_eq!(notebook.notes[0].title.as_deref(), Some("장보기 목록"));
        assert_eq!(
            notebook.notes[0].text,
            "fixture text 가나다\n둘째 줄 with emoji 🐈\nthird line"
        );
        assert_eq!(
            notebook.notes[0].drawing_coordinate_space,
            Some(super::super::model::MemoDrawingCoordinateSpace::AbsolutePoints)
        );
        assert_eq!(notebook.selected_note_id, notebook.notes[0].id);

        assert_eq!(notebook.notes[1].title.as_deref(), Some("Sketch"));
        assert_eq!(notebook.notes[1].strokes[0].points.len(), 3);

        // The legacy note has no `drawingCoordinateSpace` key in the fixture
        // at all (Swift omits nil optionals); it must decode to `None`, not
        // to a default value.
        assert_eq!(notebook.notes[2].drawing_coordinate_space, None);
        assert_eq!(notebook.notes[2].strokes[0].points.len(), 2);

        assert!(notebook.notes[3].is_empty());
    }

    // Compat (criterion 4b, Rust -> Swift): writes a fixed, known notebook
    // with the Rust store to a deterministic temp dir so `compat/check.sh`
    // can point `compat/swift-reader read <dir>` at it and compare. Ignored
    // by default (fixed path + intentional side effect on disk instead of a
    // throwaway per-test tempdir); run explicitly via
    // `cargo test --lib -- --ignored --exact core::store::tests::write_fixture_for_swift_reader --nocapture`.
    #[test]
    #[ignore]
    fn write_fixture_for_swift_reader() {
        let dir = std::env::temp_dir().join("memopet-compat-rust-output");
        let _ = fs::remove_dir_all(&dir);
        let mut store = MemoNotebookStore::new(&dir).unwrap();

        let note_a = MemoNote {
            title: Some("Rust Fixture 다시".to_string()),
            text: "rust text line1\nrust text line2 emoji 🦀".to_string(),
            ..MemoNote::new()
        };
        let note_b = MemoNote {
            strokes: vec![super::super::model::MemoStroke {
                // A pen width the Swift app does not know about; it must ignore it.
                width: Some(5.0),
                points: vec![
                    super::super::model::MemoPoint { x: 1.0, y: 2.0 },
                    super::super::model::MemoPoint { x: 3.5, y: 4.5 },
                    super::super::model::MemoPoint { x: 10.0, y: 0.0 },
                    super::super::model::MemoPoint { x: 0.0, y: 10.0 },
                ],
            }],
            ..MemoNote::new()
        };
        let note_c = MemoNote {
            title: Some("Legacy".to_string()),
            text: "legacy from rust".to_string(),
            strokes: vec![super::super::model::MemoStroke {
                width: None,
                points: vec![
                    super::super::model::MemoPoint { x: 0.2, y: 0.4 },
                    super::super::model::MemoPoint { x: 0.6, y: 0.8 },
                ],
            }],
            drawing_coordinate_space: None,
            ..MemoNote::new()
        };
        let selected_id = note_a.id;
        let notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: selected_id,
            notes: vec![note_a, note_b, note_c],
        };

        store.save(&notebook).unwrap();
        println!("COMPAT_RUST_DIR={}", dir.display());
    }

    #[test]
    fn import_from_dir_rejects_newer_version() {
        let source = tempfile::tempdir().unwrap();
        let note_id = Uuid::new_v4();
        let json = format!(
            r#"{{"version": 999, "selectedNoteID": "{note_id}", "notes": [{{"id": "{note_id}", "text": "Future", "strokes": []}}]}}"#
        );
        fs::write(source.path().join("notes.json"), json).unwrap();
        let mut into = MemoNotebook::new();

        let result = MemoNotebookStore::import_from_dir(source.path(), &mut into);

        assert!(matches!(result, Err(StoreError::UnsupportedVersion(999))));
    }
}
