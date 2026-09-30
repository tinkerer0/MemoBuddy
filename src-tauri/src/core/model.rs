//! CONTRACT (fixed by the coordinator): type names, field names, serde names
//! and the listed method signatures. Implementations may change; signatures
//! may only be extended.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct MemoPoint {
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct MemoStroke {
    pub points: Vec<MemoPoint>,
    /// Line width in points. Absent in older files (and in the Swift app,
    /// which ignores it): drawn at the default 2.75.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub width: Option<f64>,
}

/// `None` in `MemoNote::drawing_coordinate_space` means legacy normalized
/// (0...1) coordinates that must be converted with the canvas size.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MemoDrawingCoordinateSpace {
    #[serde(rename = "absolutePoints")]
    AbsolutePoints,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MemoNote {
    #[serde(with = "uuid_upper")]
    pub id: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub text: String,
    pub strokes: Vec<MemoStroke>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub drawing_coordinate_space: Option<MemoDrawingCoordinateSpace>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MemoNotebook {
    pub version: i64,
    pub notes: Vec<MemoNote>,
    #[serde(rename = "selectedNoteID", with = "uuid_upper")]
    pub selected_note_id: Uuid,
}

pub const CURRENT_VERSION: i64 = 4;

/// Widest pen the app offers is 5; anything above this in a file is clamped.
pub const MAX_STROKE_WIDTH: f64 = 40.0;

/// Renders a UUID the way Swift's `UUID().uuidString` does (uppercase,
/// hyphenated). Shared by JSON (de)serialization here and by the mobile
/// mirror's HTML ids/hrefs in `mirror.rs`.
pub(crate) fn uuid_upper_string(id: Uuid) -> String {
    let mut s = id.to_string();
    s.make_ascii_uppercase();
    s
}

/// serde helper: (de)serialize `Uuid` as an uppercase hyphenated string, to
/// stay byte-compatible with the Swift app's `notes.json`.
mod uuid_upper {
    use super::uuid_upper_string;
    use serde::de::Error as _;
    use serde::{Deserialize, Deserializer, Serializer};
    use uuid::Uuid;

    pub fn serialize<S: Serializer>(id: &Uuid, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&uuid_upper_string(*id))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Uuid, D::Error> {
        let s = String::deserialize(deserializer)?;
        Uuid::parse_str(&s).map_err(D::Error::custom)
    }
}

impl Default for MemoNote {
    fn default() -> Self {
        Self::new()
    }
}

impl MemoNote {
    pub fn new() -> Self {
        Self {
            id: Uuid::new_v4(),
            title: None,
            text: String::new(),
            strokes: Vec::new(),
            drawing_coordinate_space: Some(MemoDrawingCoordinateSpace::AbsolutePoints),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.title.as_ref().is_none_or(|t| t.is_empty())
            && self.text.is_empty()
            && self.strokes.is_empty()
    }
}

impl Default for MemoNotebook {
    fn default() -> Self {
        Self::new()
    }
}

impl MemoNotebook {
    /// One blank note, selected.
    pub fn new() -> Self {
        let note = MemoNote::new();
        let id = note.id;
        Self {
            version: CURRENT_VERSION,
            notes: vec![note],
            selected_note_id: id,
        }
    }

    pub fn selected_index(&self) -> usize {
        self.notes
            .iter()
            .position(|note| note.id == self.selected_note_id)
            .unwrap_or(0)
    }

    /// Convenience extension (not part of the original stub list): mirrors
    /// Swift's `selectedNote` computed property (`notes[selectedIndex]`).
    /// Notes is maintained as never-empty by `new`/`normalize`/`add_note`/
    /// `delete_note`, so `selected_index()` is always a valid index.
    pub fn selected_note(&self) -> &MemoNote {
        &self.notes[self.selected_index()]
    }

    /// Same rules as Swift `normalize(sanitizeContent:)`.
    pub fn normalize(&mut self, sanitize_content: bool) {
        self.version = CURRENT_VERSION;

        if self.notes.is_empty() {
            let note = MemoNote::new();
            self.selected_note_id = note.id;
            self.notes = vec![note];
            return;
        }

        let mut seen_ids: std::collections::HashSet<Uuid> = std::collections::HashSet::new();
        for note in self.notes.iter_mut() {
            if seen_ids.contains(&note.id) {
                note.id = Uuid::new_v4();
            }
            seen_ids.insert(note.id);

            if sanitize_content {
                let coordinate_maximum: Option<f64> = if note.drawing_coordinate_space.is_none() {
                    Some(1.0)
                } else {
                    None
                };
                for stroke in note.strokes.iter_mut() {
                    stroke.width = stroke.width.filter(|w| w.is_finite() && *w > 0.0).map(|w| w.min(MAX_STROKE_WIDTH));
                    for point in stroke.points.iter_mut() {
                        let x = point.x.max(0.0);
                        let y = point.y.max(0.0);
                        point.x = coordinate_maximum.map(|max| x.min(max)).unwrap_or(x);
                        point.y = coordinate_maximum.map(|max| y.min(max)).unwrap_or(y);
                    }
                }
            }
        }

        if !self
            .notes
            .iter()
            .any(|note| note.id == self.selected_note_id)
        {
            self.selected_note_id = self.notes[0].id;
        }
    }

    pub fn select(&mut self, index: usize) {
        if let Some(note) = self.notes.get(index) {
            self.selected_note_id = note.id;
        }
    }

    /// Appends a blank note, selects it and returns its id.
    #[allow(clippy::should_implement_trait)]
    pub fn add_note(&mut self) -> Uuid {
        let note = MemoNote::new();
        let id = note.id;
        self.notes.push(note);
        self.selected_note_id = id;
        id
    }

    /// Same rules as Swift `deleteNote(at:)` (never leaves zero notes).
    pub fn delete_note(&mut self, index: usize) {
        if index >= self.notes.len() {
            return;
        }
        let deleted_id = self.notes[index].id;
        self.notes.remove(index);

        if self.notes.is_empty() {
            let replacement = MemoNote::new();
            self.selected_note_id = replacement.id;
            self.notes = vec![replacement];
            return;
        }

        if self.selected_note_id == deleted_id {
            let next_index = index.min(self.notes.len() - 1);
            self.selected_note_id = self.notes[next_index].id;
        }
    }

    /// Moves the note at `from` so it ends at `to` (tab reordering). Keeps the
    /// selected note id. Out-of-range indexes are ignored.
    pub fn move_note(&mut self, from: usize, to: usize) {
        if from >= self.notes.len() || to >= self.notes.len() || from == to {
            return;
        }
        let note = self.notes.remove(from);
        self.notes.insert(to, note);
    }

    /// Trims whitespace, empty becomes `None`, at most 80 characters.
    pub fn rename_note(&mut self, index: usize, title: &str) {
        let Some(note) = self.notes.get_mut(index) else {
            return;
        };
        let trimmed = title.trim();
        if trimmed.is_empty() {
            note.title = None;
        } else {
            note.title = Some(trimmed.chars().take(80).collect());
        }
    }
}

/// Swift `MemoDrawingCoordinates.convertingLegacyNormalizedStrokes`.
pub fn converting_legacy_normalized_strokes(
    strokes: &[MemoStroke],
    canvas_width: f64,
    canvas_height: f64,
) -> Vec<MemoStroke> {
    if !canvas_width.is_finite()
        || !canvas_height.is_finite()
        || canvas_width <= 0.0
        || canvas_height <= 0.0
    {
        return strokes.to_vec();
    }

    strokes
        .iter()
        .map(|stroke| MemoStroke {
            width: None,
            points: stroke
                .points
                .iter()
                .map(|point| MemoPoint {
                    x: point.x * canvas_width,
                    y: point.y * canvas_height,
                })
                .collect(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(x: f64, y: f64) -> MemoPoint {
        MemoPoint { x, y }
    }

    // Swift: testEmptyNotebookNormalizesToOneBlankNote
    #[test]
    fn empty_notebook_normalizes_to_one_blank_note() {
        let mut notebook = MemoNotebook::new();
        notebook.notes.clear();

        notebook.normalize(true);

        assert_eq!(notebook.notes.len(), 1);
        assert_eq!(notebook.selected_note().text, "");
        assert!(notebook.selected_note().strokes.is_empty());
        assert_eq!(notebook.selected_index(), 0);
    }

    // Swift: testAddingNotesSelectsTheNewNote
    #[test]
    fn adding_notes_selects_the_new_note() {
        let mut notebook = MemoNotebook::new();
        let original_id = notebook.selected_note_id;

        let added_id = notebook.add_note();

        assert_eq!(notebook.notes.len(), 2);
        assert_eq!(notebook.selected_note_id, added_id);
        assert_eq!(notebook.selected_note().text, "");
        assert!(notebook.selected_note().strokes.is_empty());
        assert_ne!(notebook.selected_note_id, original_id);
    }

    // Swift: testDeletingSelectedNoteChoosesTheNextAvailableNote
    #[test]
    fn deleting_selected_note_chooses_the_next_available_note() {
        let first = MemoNote {
            text: "First".into(),
            ..MemoNote::new()
        };
        let second = MemoNote::new();
        let third = MemoNote {
            text: "Third".into(),
            ..MemoNote::new()
        };
        let mut notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: second.id,
            notes: vec![first.clone(), second.clone(), third.clone()],
        };

        notebook.delete_note(notebook.selected_index());

        assert_eq!(
            notebook.notes.iter().map(|n| n.id).collect::<Vec<_>>(),
            vec![first.id, third.id]
        );
        assert_eq!(notebook.selected_note_id, third.id);
    }

    // Swift: testDeletingOnlyNoteCreatesBlankReplacement
    #[test]
    fn deleting_only_note_creates_blank_replacement() {
        let note = MemoNote {
            strokes: vec![MemoStroke {
                width: None,
                points: vec![point(0.5, 0.5)],
            }],
            ..MemoNote::new()
        };
        let mut notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: note.id,
            notes: vec![note],
        };

        notebook.delete_note(notebook.selected_index());

        assert_eq!(notebook.notes.len(), 1);
        assert_eq!(notebook.selected_note().text, "");
        assert!(notebook.selected_note().strokes.is_empty());
    }

    // Swift: testDeletingAnotherNoteKeepsTheCurrentSelection
    #[test]
    fn deleting_another_note_keeps_the_current_selection() {
        let first = MemoNote {
            title: Some("First".into()),
            ..MemoNote::new()
        };
        let second = MemoNote {
            title: Some("Second".into()),
            ..MemoNote::new()
        };
        let third = MemoNote {
            title: Some("Third".into()),
            ..MemoNote::new()
        };
        let mut notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: second.id,
            notes: vec![first.clone(), second.clone(), third.clone()],
        };

        notebook.delete_note(0);

        assert_eq!(
            notebook.notes.iter().map(|n| n.id).collect::<Vec<_>>(),
            vec![second.id, third.id]
        );
        assert_eq!(notebook.selected_note_id, second.id);
    }

    // Swift: testNoteIsEmptyOnlyWhenItHasNoTitleTextOrDrawing
    #[test]
    fn note_is_empty_only_when_it_has_no_title_text_or_drawing() {
        assert!(MemoNote::new().is_empty());
        assert!(!MemoNote {
            title: Some("Title".into()),
            ..MemoNote::new()
        }
        .is_empty());
        assert!(!MemoNote {
            text: "Text".into(),
            ..MemoNote::new()
        }
        .is_empty());
        assert!(!MemoNote {
            strokes: vec![MemoStroke {
                width: None,
                points: vec![point(1.0, 1.0)]
            }],
            ..MemoNote::new()
        }
        .is_empty());
    }

    // Swift: testNormalizeRepairsDuplicateIDsAndNegativeAbsoluteDrawingPoints
    #[test]
    fn normalize_repairs_duplicate_ids_and_negative_absolute_drawing_points() {
        let duplicate_id = Uuid::new_v4();
        let mut notebook = MemoNotebook {
            version: 1,
            selected_note_id: duplicate_id,
            notes: vec![
                MemoNote {
                    id: duplicate_id,
                    ..MemoNote::new()
                },
                MemoNote {
                    id: duplicate_id,
                    strokes: vec![MemoStroke {
                        width: None,
                        points: vec![point(-20.0, 30.0)],
                    }],
                    ..MemoNote::new()
                },
            ],
        };

        notebook.normalize(true);

        let unique_ids: std::collections::HashSet<Uuid> =
            notebook.notes.iter().map(|n| n.id).collect();
        assert_eq!(unique_ids.len(), 2);
        assert_eq!(notebook.notes[1].strokes[0].points[0], point(0.0, 30.0));
        assert_eq!(notebook.version, CURRENT_VERSION);
        assert_eq!(notebook.selected_note_id, duplicate_id);
    }

    // Swift: testNormalizeClampsLegacyNormalizedDrawingPoints
    #[test]
    fn normalize_clamps_legacy_normalized_drawing_points() {
        let note = MemoNote {
            strokes: vec![MemoStroke {
                width: None,
                points: vec![point(-20.0, 30.0)],
            }],
            drawing_coordinate_space: None,
            ..MemoNote::new()
        };
        let id = note.id;
        let mut notebook = MemoNotebook {
            version: 2,
            selected_note_id: id,
            notes: vec![note],
        };

        notebook.normalize(true);

        assert_eq!(
            notebook.selected_note().strokes[0].points[0],
            point(0.0, 1.0)
        );
        assert_eq!(notebook.selected_note().drawing_coordinate_space, None);
    }

    // Swift: testConvertingLegacyDrawingUsesCanvasSizeOnce
    #[test]
    fn converting_legacy_drawing_uses_canvas_size_once() {
        let legacy = vec![MemoStroke {
            width: None,
            points: vec![point(0.25, 0.5), point(1.0, 0.0)],
        }];

        let converted = converting_legacy_normalized_strokes(&legacy, 320.0, 180.0);

        assert_eq!(
            converted,
            vec![MemoStroke {
                width: None,
                points: vec![point(80.0, 90.0), point(320.0, 0.0)],
            }]
        );
        assert_eq!(legacy[0].points[0], point(0.25, 0.5));
    }

    // Swift: testNormalizePreservesAbsolutePointsOutsideCurrentCanvas
    #[test]
    fn normalize_preserves_absolute_points_outside_current_canvas() {
        let note = MemoNote {
            strokes: vec![MemoStroke {
                width: None,
                points: vec![point(480.0, 310.0)],
            }],
            ..MemoNote::new()
        };
        let id = note.id;
        let mut notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: id,
            notes: vec![note],
        };

        notebook.normalize(true);

        assert_eq!(
            notebook.selected_note().strokes[0].points[0],
            point(480.0, 310.0)
        );
        assert_eq!(
            notebook.selected_note().drawing_coordinate_space,
            Some(MemoDrawingCoordinateSpace::AbsolutePoints)
        );
    }

    // Not ported: Swift testEraserDragSplitsAStrokeWithoutJoiningAcrossTheGap,
    // testEraserRemovesOnlyTouchedDots, testEraserLeavesDistantStrokesUnchanged
    // (MemoDrawingEraser has no counterpart in this Rust contract's model.rs;
    // no `todo!()` stub exists for it, so it is out of scope here).

    // New: exercises `move_note` (not present in the Swift core; added for
    // tab reordering per the Rust contract's doc comment).
    #[test]
    fn move_note_reorders_and_keeps_selection() {
        let first = MemoNote::new();
        let second = MemoNote::new();
        let third = MemoNote::new();
        let mut notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: first.id,
            notes: vec![first.clone(), second.clone(), third.clone()],
        };

        notebook.move_note(0, 2);

        assert_eq!(
            notebook.notes.iter().map(|n| n.id).collect::<Vec<_>>(),
            vec![second.id, third.id, first.id]
        );
        assert_eq!(
            notebook.selected_note_id, first.id,
            "selection follows the moved note by id"
        );
    }

    #[test]
    fn move_note_to_earlier_index_shifts_others_right() {
        let first = MemoNote::new();
        let second = MemoNote::new();
        let third = MemoNote::new();
        let mut notebook = MemoNotebook {
            version: CURRENT_VERSION,
            selected_note_id: third.id,
            notes: vec![first.clone(), second.clone(), third.clone()],
        };

        notebook.move_note(2, 0);

        assert_eq!(
            notebook.notes.iter().map(|n| n.id).collect::<Vec<_>>(),
            vec![third.id, first.id, second.id]
        );
    }

    #[test]
    fn move_note_ignores_out_of_range_indexes() {
        let mut notebook = MemoNotebook::new();
        notebook.add_note();
        let before = notebook.notes.iter().map(|n| n.id).collect::<Vec<_>>();

        notebook.move_note(0, 99);
        notebook.move_note(99, 0);
        notebook.move_note(5, 9);

        assert_eq!(
            notebook.notes.iter().map(|n| n.id).collect::<Vec<_>>(),
            before
        );
    }

    // New: exercises `rename_note` (not present in the Swift core).
    #[test]
    fn rename_note_trims_and_sets_title() {
        let mut notebook = MemoNotebook::new();

        notebook.rename_note(0, "  My Note  ");

        assert_eq!(notebook.notes[0].title.as_deref(), Some("My Note"));
    }

    #[test]
    fn rename_note_blank_after_trim_clears_title() {
        let mut notebook = MemoNotebook::new();
        notebook.rename_note(0, "Something");

        notebook.rename_note(0, "   \n\t  ");

        assert_eq!(notebook.notes[0].title, None);
    }

    #[test]
    fn rename_note_truncates_to_eighty_characters() {
        let mut notebook = MemoNotebook::new();
        let long_title = "가".repeat(100);

        notebook.rename_note(0, &long_title);

        let title = notebook.notes[0].title.as_ref().unwrap();
        assert_eq!(title.chars().count(), 80);
        assert_eq!(*title, "가".repeat(80));
    }

    #[test]
    fn rename_note_ignores_out_of_range_index() {
        let mut notebook = MemoNotebook::new();

        notebook.rename_note(7, "no such note");

        assert!(notebook.notes.iter().all(|n| n.title.is_none()));
    }

    // Serialization compatibility with the Swift app.
    #[test]
    fn note_id_serializes_as_uppercase_uuid_string() {
        let notebook = MemoNotebook::new();
        let json = serde_json::to_string(&notebook).unwrap();

        assert!(json.contains(&uuid_upper_string(notebook.notes[0].id)));
        assert!(
            !json.contains(&notebook.notes[0].id.to_string()),
            "must not contain the lowercase form"
        );
        assert!(json.contains("\"selectedNoteID\""));
    }

    #[test]
    fn note_round_trips_through_json_with_uppercase_uuid_input() {
        let json = r#"{"version":4,"selectedNoteID":"E5B7C0B2-6E9E-4B0E-9C36-9B7B6B2B6B2B","notes":[{"id":"E5B7C0B2-6E9E-4B0E-9C36-9B7B6B2B6B2B","text":"hi","strokes":[]}]}"#;
        let notebook: MemoNotebook = serde_json::from_str(json).unwrap();
        assert_eq!(notebook.notes[0].text, "hi");
        assert_eq!(notebook.notes[0].title, None);
        assert_eq!(notebook.notes[0].drawing_coordinate_space, None);
    }
}

#[cfg(test)]
mod stroke_width_tests {
    use super::*;

    #[test]
    fn stroke_width_round_trips_and_is_omitted_when_absent() {
        let stroke = MemoStroke { points: vec![MemoPoint { x: 1.0, y: 2.0 }], width: Some(5.0) };
        let json = serde_json::to_string(&stroke).unwrap();
        assert_eq!(json, r#"{"points":[{"x":1.0,"y":2.0}],"width":5.0}"#);
        assert_eq!(serde_json::from_str::<MemoStroke>(&json).unwrap(), stroke);
        let plain = MemoStroke { points: vec![], width: None };
        assert_eq!(serde_json::to_string(&plain).unwrap(), r#"{"points":[]}"#);
        assert_eq!(serde_json::from_str::<MemoStroke>(r#"{"points":[]}"#).unwrap(), plain);
    }

    #[test]
    fn normalize_drops_invalid_widths_and_clamps_huge_ones() {
        let mut notebook = MemoNotebook::new();
        notebook.notes[0].strokes = vec![
            MemoStroke { points: vec![], width: Some(-1.0) },
            MemoStroke { points: vec![], width: Some(1e9) },
            MemoStroke { points: vec![], width: Some(3.0) },
        ];
        notebook.normalize(true);
        let widths: Vec<Option<f64>> = notebook.notes[0].strokes.iter().map(|s| s.width).collect();
        assert_eq!(widths, vec![None, Some(MAX_STROKE_WIDTH), Some(3.0)]);
    }
}
