//! CONTRACT: port of Swift `MobileMirrorExporter` (render + write) and
//! `MobileMirrorWriteSchedule` (monotonic seconds).
//!
//! Not ported: Swift `MobileMirrorFolderBookmark` (`make`/`resolve`) and its
//! test `testFolderBookmarkRoundTripsSelectedDirectory`. That type wraps
//! AppKit/Foundation security-scoped bookmarks (`URL.bookmarkData` /
//! `URL(resolvingBookmarkData:)`), which have no cross-platform equivalent
//! and no counterpart `todo!()` in this contract's `mirror.rs` — Tauri's
//! folder-permission story (e.g. `tauri-plugin-dialog` scoped paths, see
//! `docs/PLAN.md`) is expected to replace it at the app layer, not in core.

use std::path::{Path, PathBuf};

use super::fsutil;
use super::model::{uuid_upper_string, MemoNote, MemoNotebook};

pub const FILE_NAME: &str = "MemoPet Mobile.html";
pub const MINIMUM_INTERVAL_SECS: f64 = 30.0;

/// Seconds to wait before the next write; 0 means write now. A time that
/// appears to run backwards waits a full interval.
pub fn write_delay(last_write: Option<f64>, now: f64, interval: f64) -> f64 {
    let Some(last_write) = last_write else {
        return 0.0;
    };
    let elapsed = (now - last_write).max(0.0);
    (interval - elapsed).max(0.0)
}

/// `generated_at` is an RFC 3339 UTC timestamp with milliseconds.
pub fn render(notebook: &MemoNotebook, generated_at: &str) -> String {
    let mut normalized = notebook.clone();
    normalized.normalize(true);

    let count_label = if normalized.notes.len() == 1 {
        "1 note".to_string()
    } else {
        format!("{} notes", normalized.notes.len())
    };

    let navigation = normalized
        .notes
        .iter()
        .enumerate()
        .map(|(index, note)| {
            let selected = note.id == normalized.selected_note_id;
            let current = if selected {
                " aria-current=\"true\""
            } else {
                ""
            };
            format!(
                "<a href=\"#note-{id}\"{current}>{title}</a>",
                id = uuid_upper_string(note.id),
                current = current,
                title = escape(&note_title(note, index)),
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let sections = normalized
        .notes
        .iter()
        .enumerate()
        .map(|(index, note)| render_note(note, index, note.id == normalized.selected_note_id))
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r#"<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow, noarchive">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>MemoPet Mobile</title>
{style}
</head>
<body>
<main>
<header>
<p class="eyebrow">MemoPet mobile mirror</p>
<h1>Your notes</h1>
<p class="meta">Updated <time datetime="{timestamp}">{timestamp}</time> · {count_label} · Read-only</p>
</header>
<nav aria-label="Notes">
{navigation}
</nav>
{sections}
</main>
</body>
</html>"#,
        style = STYLE_BLOCK,
        timestamp = escape(generated_at),
        count_label = count_label,
        navigation = navigation,
        sections = sections,
    )
}

pub fn write(notebook: &MemoNotebook, dir: &Path, generated_at: &str) -> std::io::Result<PathBuf> {
    if !dir.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "The Mobile Mirror destination is missing or is not a folder.",
        ));
    }

    let output_path = dir.join(FILE_NAME);
    let html = render(notebook, generated_at);
    fsutil::write_atomic(&output_path, html.as_bytes())?;
    Ok(output_path)
}

const STYLE_BLOCK: &str = r#"<style>
:root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
* { box-sizing: border-box; }
body { margin: 0; background: #f3f4f6; color: #171717; }
main { width: min(100% - 24px, 760px); margin: 0 auto; padding: 28px 0 56px; }
header { margin-bottom: 18px; }
.eyebrow { margin: 0 0 6px; color: #b45309; font-size: .78rem; font-weight: 750; letter-spacing: .08em; text-transform: uppercase; }
h1 { margin: 0; font-size: clamp(1.8rem, 8vw, 2.7rem); letter-spacing: -.04em; }
.meta { margin: 8px 0 0; color: #6b7280; font-size: .9rem; }
nav { display: flex; gap: 8px; overflow-x: auto; margin: 0 0 16px; padding: 2px 1px 8px; }
nav a { flex: 0 0 auto; max-width: 240px; overflow: hidden; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 999px; color: inherit; text-decoration: none; text-overflow: ellipsis; white-space: nowrap; }
nav a[aria-current="true"] { border-color: #f59e0b; background: #fef3c7; color: #78350f; }
.note { margin: 0 0 14px; padding: 18px; border: 1px solid #e5e7eb; border-radius: 18px; background: #fff; box-shadow: 0 8px 28px rgb(15 23 42 / 6%); }
.note.selected { border-color: #f59e0b; }
.note-heading { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
h2 { min-width: 0; margin: 0; overflow-wrap: anywhere; font-size: 1.15rem; }
.badge { flex: 0 0 auto; color: #92400e; font-size: .75rem; font-weight: 700; }
.note-text { min-height: 1.5em; overflow-wrap: anywhere; white-space: pre-wrap; line-height: 1.55; }
.empty { margin: 0; color: #9ca3af; font-style: italic; }
figure { margin: 16px 0 0; }
figcaption { margin-bottom: 7px; color: #6b7280; font-size: .8rem; }
svg { display: block; width: 100%; height: auto; max-height: 520px; border: 1px solid #e5e7eb; border-radius: 12px; background: #fafafa; color: #171717; }
@media (prefers-color-scheme: dark) {
body { background: #111827; color: #f9fafb; }
.meta, figcaption { color: #9ca3af; }
nav a { border-color: #4b5563; }
nav a[aria-current="true"] { border-color: #fbbf24; background: #451a03; color: #fef3c7; }
.note { border-color: #374151; background: #1f2937; box-shadow: none; }
.note.selected { border-color: #fbbf24; }
.badge { color: #fcd34d; }
svg { border-color: #4b5563; background: #111827; color: #f9fafb; }
}
</style>"#;

fn render_note(note: &MemoNote, index: usize, is_selected: bool) -> String {
    let title = escape(&note_title(note, index));
    let selected_class = if is_selected { " selected" } else { "" };
    let badge = if is_selected {
        "<span class=\"badge\">Current note</span>"
    } else {
        ""
    };
    let text = if note.text.is_empty() {
        "<p class=\"empty\">No text in this note.</p>".to_string()
    } else {
        format!(
            "<div class=\"note-text\" dir=\"auto\">{}</div>",
            escape(&note.text)
        )
    };
    let drawing = render_drawing(note, &title, index);

    format!(
        "<section class=\"note{selected_class}\" id=\"note-{id}\">\n<div class=\"note-heading\">\n<h2 dir=\"auto\">{title}</h2>\n{badge}\n</div>\n{text}\n{drawing}\n</section>",
        selected_class = selected_class,
        id = uuid_upper_string(note.id),
        title = title,
        badge = badge,
        text = text,
        drawing = drawing,
    )
}

fn render_drawing(note: &MemoNote, title: &str, index: usize) -> String {
    const LEGACY_CANVAS_WIDTH: f64 = 320.0;
    const LEGACY_CANVAS_HEIGHT: f64 = 180.0;

    let strokes: Vec<Vec<(f64, f64)>> = note
        .strokes
        .iter()
        .filter_map(|stroke| {
            let points: Vec<(f64, f64)> = stroke
                .points
                .iter()
                .map(|point| {
                    let is_legacy = note.drawing_coordinate_space.is_none();
                    let projected_x = if is_legacy {
                        point.x * LEGACY_CANVAS_WIDTH
                    } else {
                        point.x
                    };
                    let projected_y = if is_legacy {
                        point.y * LEGACY_CANVAS_HEIGHT
                    } else {
                        point.y
                    };
                    (safe_coordinate(projected_x), safe_coordinate(projected_y))
                })
                .collect();
            if points.is_empty() {
                None
            } else {
                Some(points)
            }
        })
        .collect();

    if strokes.is_empty() {
        return String::new();
    }

    let max_x = strokes
        .iter()
        .flatten()
        .map(|p| p.0)
        .fold(0.0_f64, f64::max);
    let max_y = strokes
        .iter()
        .flatten()
        .map(|p| p.1)
        .fold(0.0_f64, f64::max);
    let width = (max_x + 12.0).ceil().clamp(320.0, 4_096.0);
    let height = (max_y + 12.0).ceil().clamp(180.0, 4_096.0);

    let shapes = strokes
        .iter()
        .map(|points| {
            if points.len() <= 1 {
                let (x, y) = points[0];
                format!(
                    "<circle cx=\"{}\" cy=\"{}\" r=\"2.25\" fill=\"currentColor\" />",
                    format_number(x),
                    format_number(y)
                )
            } else {
                let coordinates = points
                    .iter()
                    .map(|(x, y)| format!("{},{}", format_number(*x), format_number(*y)))
                    .collect::<Vec<_>>()
                    .join(" ");
                format!(
                    "<polyline points=\"{coordinates}\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\" />"
                )
            }
        })
        .collect::<Vec<_>>()
        .join("\n");
    let drawing_title_id = format!("drawing-title-{}-{}", index + 1, uuid_upper_string(note.id));

    format!(
        "<figure>\n<figcaption>Drawing</figcaption>\n<svg viewBox=\"0 0 {w} {h}\" role=\"img\" aria-labelledby=\"{tid}\">\n<title id=\"{tid}\">Drawing for {title}</title>\n{shapes}\n</svg>\n</figure>",
        w = format_number(width),
        h = format_number(height),
        tid = drawing_title_id,
        title = title,
        shapes = shapes,
    )
}

fn note_title(note: &MemoNote, index: usize) -> String {
    if let Some(title) = &note.title {
        let trimmed = title.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    format!("Note {}", index + 1)
}

fn escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn safe_coordinate(value: f64) -> f64 {
    if !value.is_finite() {
        return 0.0;
    }
    value.clamp(0.0, 4_096.0)
}

fn format_number(value: f64) -> String {
    format!("{value:.3}")
}

#[cfg(test)]
mod generated_at_tests {
    use super::*;

    // Review question: the timestamp is caller-provided text.
    #[test]
    fn generated_at_is_escaped() {
        let html = render(&MemoNotebook::new(), "<script>x</script>\"'");
        assert!(!html.contains("<script>x"));
        assert!(html.contains("&lt;script&gt;x&lt;/script&gt;"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::model::{MemoDrawingCoordinateSpace, MemoPoint, MemoStroke};

    // Swift: testWriteScheduleWritesImmediatelyWithoutPreviousWrite
    #[test]
    fn write_schedule_writes_immediately_without_previous_write() {
        assert_eq!(write_delay(None, 1_000.0, MINIMUM_INTERVAL_SECS), 0.0);
    }

    // Swift: testWriteScheduleWaitsForRemainderOfInterval
    #[test]
    fn write_schedule_waits_for_remainder_of_interval() {
        let delay = write_delay(Some(1_000.0), 1_010.0, 30.0);
        assert!((delay - 20.0).abs() < 0.001);
    }

    // Swift: testWriteScheduleWritesImmediatelyOnceIntervalHasElapsed
    #[test]
    fn write_schedule_writes_immediately_once_interval_has_elapsed() {
        assert_eq!(write_delay(Some(1_000.0), 1_030.0, 30.0), 0.0);
    }

    // Swift: testWriteScheduleKeepsLimitWhenTimeRunsBackwards
    #[test]
    fn write_schedule_keeps_limit_when_time_runs_backwards() {
        assert_eq!(write_delay(Some(1_000.0), 995.0, 30.0), 30.0);
    }

    // Swift: testRenderIsSelfContainedAndEscapesNoteContent
    #[test]
    fn render_is_self_contained_and_escapes_note_content() {
        let note = MemoNote {
            title: Some("<script>alert(\"title\")</script> & 'quote'".to_string()),
            text: "<img src=x onerror=alert(1)>\n안녕 & goodbye".to_string(),
            ..MemoNote::new()
        };
        let id = note.id;
        let notebook = MemoNotebook {
            version: crate::core::model::CURRENT_VERSION,
            selected_note_id: id,
            notes: vec![note],
        };

        let html = render(&notebook, "1970-01-01T00:00:00.000Z");

        assert!(!html.contains("<script>"));
        assert!(!html.contains("<img src="));
        assert!(!html.contains("http://"));
        assert!(!html.contains("https://"));
        assert!(html.contains(
            "&lt;script&gt;alert(&quot;title&quot;)&lt;/script&gt; &amp; &#39;quote&#39;"
        ));
        assert!(html.contains("&lt;img src=x onerror=alert(1)&gt;\n안녕 &amp; goodbye"));
        assert!(html.contains("default-src 'none'"));
        assert!(html.contains("1970-01-01T00:00:00.000Z"));
    }

    // Swift: testRenderIncludesSelectedNoteAndLegacyAndAbsoluteDrawings
    #[test]
    fn render_includes_selected_note_and_legacy_and_absolute_drawings() {
        let legacy = MemoNote {
            text: "Legacy drawing".to_string(),
            strokes: vec![MemoStroke {
                width: None,
                points: vec![MemoPoint { x: 0.25, y: 0.5 }, MemoPoint { x: 0.75, y: 1.0 }],
            }],
            drawing_coordinate_space: None,
            ..MemoNote::new()
        };
        let absolute = MemoNote {
            title: Some("Dot".to_string()),
            strokes: vec![MemoStroke {
                width: None,
                points: vec![MemoPoint { x: 12.0, y: 24.0 }],
            }],
            drawing_coordinate_space: Some(MemoDrawingCoordinateSpace::AbsolutePoints),
            ..MemoNote::new()
        };
        let absolute_id = absolute.id;
        let notebook = MemoNotebook {
            version: crate::core::model::CURRENT_VERSION,
            selected_note_id: absolute_id,
            notes: vec![legacy, absolute],
        };

        let html = render(&notebook, "2026-01-01T00:00:00.000Z");

        assert!(html.contains(&format!(
            "href=\"#note-{}\" aria-current=\"true\"",
            uuid_upper_string(absolute_id)
        )));
        assert!(html.contains("80.000,90.000 240.000,180.000"));
        assert!(html.contains("<circle cx=\"12.000\" cy=\"24.000\""));
        assert_eq!(html.matches("<svg ").count(), 2);
    }

    // Swift: testWriteCreatesAndUpdatesNamedHTMLFile
    #[test]
    fn write_creates_and_updates_named_html_file() {
        let dir = tempfile::tempdir().unwrap();
        let first = MemoNotebook {
            version: crate::core::model::CURRENT_VERSION,
            selected_note_id: uuid::Uuid::new_v4(),
            notes: vec![MemoNote {
                text: "First".to_string(),
                ..MemoNote::new()
            }],
        };
        let first_id = first.notes[0].id;
        let first = MemoNotebook {
            selected_note_id: first_id,
            ..first
        };
        let second = MemoNotebook {
            version: crate::core::model::CURRENT_VERSION,
            selected_note_id: uuid::Uuid::new_v4(),
            notes: vec![MemoNote {
                text: "Second".to_string(),
                ..MemoNote::new()
            }],
        };
        let second_id = second.notes[0].id;
        let second = MemoNotebook {
            selected_note_id: second_id,
            ..second
        };

        let output_path = write(&first, dir.path(), "2026-01-01T00:00:00.000Z").unwrap();
        write(&second, dir.path(), "2026-01-01T00:00:01.000Z").unwrap();
        let contents = std::fs::read_to_string(&output_path).unwrap();

        assert_eq!(
            output_path.file_name().unwrap().to_str().unwrap(),
            FILE_NAME
        );
        assert!(!contents.contains(">First<"));
        assert!(contents.contains(">Second<"));
    }

    // Swift: testWriteRejectsMissingAndNonFileDestinations (partial: the
    // `URL(string: "https://...")!` case has no Rust equivalent since `Path`
    // is always a filesystem path, never a remote URL — see module doc).
    #[test]
    fn write_rejects_missing_and_non_directory_destinations() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("not-a-folder");
        std::fs::write(&file_path, b"").unwrap();
        let missing_path = dir.path().join("missing");
        let notebook = MemoNotebook::new();

        assert!(write(&notebook, &file_path, "2026-01-01T00:00:00.000Z").is_err());
        assert!(write(&notebook, &missing_path, "2026-01-01T00:00:00.000Z").is_err());
    }
}
