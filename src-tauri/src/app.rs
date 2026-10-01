//! App state, commands and the open/close flow shared by both platforms.
//!
//! Coordinates handed to and from `platform` are that platform's global
//! frame units (macOS: points, top-left origin; Windows: physical pixels).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::{TrayIcon, TrayIconBuilder};
use tauri::{AppHandle, Emitter, Manager, WindowEvent};
use tauri_plugin_dialog::{DialogExt, MessageDialogKind};
use uuid::Uuid;

use crate::core::model::{MemoDrawingCoordinateSpace, MemoNotebook, MemoStroke};
use crate::core::placement::{self, Rect};
use crate::core::store::MemoNotebookStore;
use crate::i18n::tr;
use crate::platform;
use crate::characters;
use crate::settings::{CharacterChoice, Settings, Theme, CHARACTER_SIZES, MAX_MEMO_SIZE, MIN_MEMO_SIZE};

pub const BUBBLE_LABEL: &str = "bubble";
#[cfg_attr(target_os = "macos", allow(dead_code))]
pub const CHARACTER_LABEL: &str = "character";
const MAX_NOTE_BYTES: usize = 1024 * 1024;
const MAX_NOTEBOOK_BYTES: usize = 16 * 1024 * 1024;
const MAX_CUSTOM_IMAGE_BYTES: u64 = 15 * 1024 * 1024;

pub struct AppState {
    pub data_dir: PathBuf,
    store: Mutex<MemoNotebookStore>,
    notebook: Mutex<MemoNotebook>,
    generations: Mutex<HashMap<Uuid, u64>>,
    pub settings: Mutex<Settings>,
    /// No settings file existed at launch: the memo opens once with the tip.
    first_run: bool,
    recovery_notice: Mutex<Option<String>>,
    tray: Mutex<Option<TrayIcon>>,
    quit: Mutex<QuitState>,
}

#[derive(Default)]
struct QuitState {
    requested: bool,
    acknowledged: bool,
    /// Bumped on every request so an old timer cannot end a newer request.
    serial: u64,
}


// ---------- DTOs ----------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteView {
    id: Uuid,
    title: Option<String>,
    text: String,
    strokes: Vec<MemoStroke>,
    drawing_coordinate_space: Option<MemoDrawingCoordinateSpace>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotebookView {
    notes: Vec<NoteView>,
    selected_id: Uuid,
    recovery_notice: Option<String>,
    /// Highest save generation accepted this session; the page starts its
    /// counter above it so a reloaded page can never look stale.
    generation_floor: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveAck {
    saved: bool,
    stale: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UiInfo {
    language: &'static str,
    platform: &'static str,
    theme: Theme,
    /// Open the memo once by itself so the tip is seen.
    first_run: bool,
    show_tip: bool,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct CloseRequest {
    explicit: bool,
}

fn view(notebook: &MemoNotebook, notice: Option<String>, generation_floor: u64) -> NotebookView {
    NotebookView {
        generation_floor,
        notes: notebook
            .notes
            .iter()
            .map(|note| NoteView {
                id: note.id,
                title: note.title.clone(),
                text: note.text.clone(),
                strokes: note.strokes.clone(),
                drawing_coordinate_space: note.drawing_coordinate_space,
            })
            .collect(),
        selected_id: notebook.selected_note_id,
        recovery_notice: notice,
    }
}

fn generation_floor(app: &AppHandle) -> u64 {
    state(app).generations.lock().unwrap().values().copied().max().unwrap_or(0)
}

// ---------- setup ----------

pub fn setup(app: &mut tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "macos")]
    app.set_activation_policy(tauri::ActivationPolicy::Accessory);

    let data_dir = app.path().app_data_dir()?;
    std::fs::create_dir_all(&data_dir)?;
    let opened = MemoNotebookStore::new(&data_dir).and_then(|mut store| store.load().map(|notebook| (store, notebook)));
    let (store, notebook) = match opened {
        Ok(pair) => pair,
        Err(error) => {
            // Leave the files exactly as they are and explain, instead of crashing.
            let message = match &error {
                crate::core::store::StoreError::UnsupportedVersion(_) => tr(
                    "이 메모는 더 새 버전의 MemoBuddy에서 만들어졌습니다. MemoBuddy를 최신 버전으로 업데이트해 주세요. 파일은 바꾸지 않았습니다.",
                    "These notes were created by a newer version of MemoBuddy. Please update MemoBuddy. The files were not changed.",
                )
                .to_owned(),
                other => format!("{} {other}", tr("메모를 열 수 없습니다.", "MemoBuddy could not open your notes.")),
            };
            let handle = app.handle().clone();
            app.dialog()
                .message(message)
                .title("MemoBuddy")
                .kind(MessageDialogKind::Error)
                .show(move |_| handle.exit(1));
            return Ok(());
        }
    };
    let notice = store.recovery_notice().map(str::to_owned);
    let first_run = !Settings::path(&data_dir).exists();
    let settings = Settings::load(&data_dir);

    app.manage(AppState {
        data_dir,
        store: Mutex::new(store),
        notebook: Mutex::new(notebook),
        generations: Mutex::new(HashMap::new()),
        settings: Mutex::new(settings.clone()),
        first_run,
        recovery_notice: Mutex::new(notice),
        tray: Mutex::new(None),
        quit: Mutex::new(QuitState::default()),
    });

    let handle = app.handle().clone();
    platform::setup(&handle, &settings)?;
    // First launch follows the system appearance. Asked after the windows
    // exist: on Windows the answer comes from a window.
    if settings.theme.is_none() {
        let theme = platform::system_theme(&handle);
        state(&handle).settings.lock().unwrap().theme = Some(theme);
        save_settings(&handle);
    }
    apply_theme(&handle);
    apply_character(&handle);
    install_tray(&handle)?;
    #[cfg(target_os = "macos")]
    install_app_menu(&handle)?;
    Ok(())
}

fn state(app: &AppHandle) -> &AppState {
    app.state::<AppState>().inner()
}

fn save_settings(app: &AppHandle) {
    let state = state(app);
    let settings = state.settings.lock().unwrap().clone();
    if let Err(error) = settings.save(&state.data_dir) {
        eprintln!("MemoBuddy: could not save settings: {error}");
    }
}

// ---------- persistence ----------

fn persist(app: &AppHandle, notebook: &MemoNotebook) -> Result<(), String> {
    state(app).store.lock().unwrap().save(notebook).map_err(|error| save_error_message(&error))
}

fn save_error_message(error: &crate::core::store::StoreError) -> String {
    use crate::core::store::StoreError;
    let reason = match error {
        StoreError::Io(io) if io.kind() == std::io::ErrorKind::PermissionDenied => {
            tr("저장 폴더에 쓸 수 있는 권한이 없습니다.", "MemoBuddy is not allowed to write to its data folder.").to_owned()
        }
        // StorageFull covers ENOSPC and Windows' ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL.
        StoreError::Io(io) if io.kind() == std::io::ErrorKind::StorageFull => tr("디스크 공간이 부족합니다.", "The disk is full.").to_owned(),
        other => other.to_string(),
    };
    format!("{} {}", tr("메모를 저장하지 못했습니다. 입력한 내용은 창에 남아 있습니다.", "Your note could not be saved. What you typed is still here."), reason)
}

fn notebook_bytes(notebook: &MemoNotebook) -> usize {
    notebook.notes.iter().map(|note| note.text.len()).sum()
}

fn index_of(notebook: &MemoNotebook, id: Uuid) -> Result<usize, String> {
    notebook
        .notes
        .iter()
        .position(|note| note.id == id)
        .ok_or_else(|| tr("메모를 찾지 못했습니다. 다시 열어 주세요.", "That note no longer exists. Reopen the memo.").to_owned())
}

/// Applies `change` to a copy, saves it, and only then makes it current, so a
/// failed save leaves the previous notebook intact.
fn mutate(app: &AppHandle, change: impl FnOnce(&mut MemoNotebook) -> Result<(), String>) -> Result<NotebookView, String> {
    let result = {
        let mut notebook = state(app).notebook.lock().unwrap();
        let mut next = notebook.clone();
        change(&mut next)?;
        persist(app, &next)?;
        *notebook = next;
        view(&notebook, None, 0)
    };
    Ok(NotebookView { generation_floor: generation_floor(app), ..result })
}

// ---------- commands ----------

#[tauri::command]
pub fn load_notebook(app: AppHandle) -> NotebookView {
    let state = state(&app);
    let notice = state.recovery_notice.lock().unwrap().take();
    let floor = generation_floor(&app);
    let notebook = state.notebook.lock().unwrap();
    view(&notebook, notice, floor)
}

#[tauri::command]
pub fn ui_info(app: AppHandle) -> UiInfo {
    let state = state(&app);
    let settings = state.settings.lock().unwrap();
    UiInfo {
        language: crate::i18n::code(),
        platform: if cfg!(target_os = "macos") { "macos" } else { "windows" },
        theme: settings.theme.unwrap_or(Theme::Light),
        first_run: state.first_run,
        show_tip: !settings.tip_seen,
    }
}

/// The memo page's first-run tip was dismissed; it does not come back.
/// Fails (and the tip stays) when the setting could not be saved.
#[tauri::command]
pub fn dismiss_tip(app: AppHandle) -> Result<(), String> {
    let state = state(&app);
    let result = state.settings.lock().unwrap().dismiss_tip(&state.data_dir);
    result.map_err(|error| format!("{} {error}", tr("설정을 저장하지 못했습니다.", "The setting could not be saved.")))
}

/// White or dark, chosen in the menu (first launch follows the system).
pub fn apply_theme(app: &AppHandle) {
    let theme = state(app).settings.lock().unwrap().theme.unwrap_or(Theme::Light);
    platform::set_theme(app, theme);
    let _ = app.emit("memo:theme", theme);
}

#[allow(clippy::too_many_arguments)]
#[tauri::command]
pub fn save_note(
    app: AppHandle,
    note_id: Uuid,
    generation: u64,
    text: String,
    strokes: Vec<MemoStroke>,
    drawing_coordinate_space: Option<MemoDrawingCoordinateSpace>,
) -> Result<SaveAck, String> {
    if text.len() > MAX_NOTE_BYTES {
        return Err(tr(
            "메모 하나는 1MB까지 저장할 수 있습니다. 입력한 내용은 창에 남아 있습니다.",
            "A note can hold up to 1 MB. Your text is still in the memo.",
        )
        .to_owned());
    }
    let state = state(&app);
    {
        let generations = state.generations.lock().unwrap();
        if generations.get(&note_id).is_some_and(|last| *last > generation) {
            return Ok(SaveAck { saved: false, stale: true });
        }
    }
    let strokes: Vec<MemoStroke> = strokes
        .into_iter()
        .map(|stroke| MemoStroke {
            width: stroke.width.filter(|w| w.is_finite() && *w > 0.0),
            points: stroke.points.into_iter().filter(|p| p.x.is_finite() && p.y.is_finite()).collect(),
        })
        .filter(|stroke| !stroke.points.is_empty())
        .collect();
    mutate(&app, |notebook| {
        let index = index_of(notebook, note_id)?;
        let note = &mut notebook.notes[index];
        note.text = text;
        note.strokes = strokes;
        note.drawing_coordinate_space = drawing_coordinate_space;
        if notebook_bytes(notebook) > MAX_NOTEBOOK_BYTES {
            return Err(tr(
                "전체 메모는 16MB까지 저장할 수 있습니다. 오래된 메모를 정리해 주세요.",
                "All notes together can hold up to 16 MB. Delete some old notes.",
            )
            .to_owned());
        }
        Ok(())
    })?;
    let mut generations = state.generations.lock().unwrap();
    let entry = generations.entry(note_id).or_insert(generation);
    *entry = (*entry).max(generation);
    Ok(SaveAck { saved: true, stale: false })
}

#[tauri::command]
pub fn select_note(app: AppHandle, note_id: Uuid) -> Result<NotebookView, String> {
    mutate(&app, |notebook| {
        let index = index_of(notebook, note_id)?;
        notebook.select(index);
        Ok(())
    })
}

#[tauri::command]
pub fn add_note(app: AppHandle) -> Result<NotebookView, String> {
    mutate(&app, |notebook| {
        if notebook.notes.len() >= 200 {
            return Err(tr("메모는 200개까지 만들 수 있습니다.", "You can keep up to 200 notes.").to_owned());
        }
        notebook.add_note();
        Ok(())
    })
}

#[tauri::command]
pub fn delete_note(app: AppHandle, note_id: Uuid) -> Result<NotebookView, String> {
    let result = mutate(&app, |notebook| {
        let index = index_of(notebook, note_id)?;
        notebook.delete_note(index);
        Ok(())
    });
    if result.is_ok() {
        state(&app).generations.lock().unwrap().remove(&note_id);
    }
    result
}

#[tauri::command]
pub fn rename_note(app: AppHandle, note_id: Uuid, title: String) -> Result<NotebookView, String> {
    mutate(&app, |notebook| {
        let index = index_of(notebook, note_id)?;
        notebook.rename_note(index, &title);
        Ok(())
    })
}

/// Moves `note_id` so it sits right before `before_id` (or last when `None`).
#[tauri::command]
pub fn move_note(app: AppHandle, note_id: Uuid, before_id: Option<Uuid>) -> Result<NotebookView, String> {
    mutate(&app, |notebook| {
        let from = index_of(notebook, note_id)?;
        let remaining: Vec<Uuid> = notebook.notes.iter().map(|note| note.id).filter(|id| *id != note_id).collect();
        let to = match before_id {
            Some(before) => remaining.iter().position(|id| *id == before).unwrap_or(remaining.len()),
            None => remaining.len(),
        };
        notebook.move_note(from, to);
        Ok(())
    })
}

/// Called by the memo page after it saved everything it had.
#[tauri::command]
pub fn close_bubble(app: AppHandle, explicit: bool) {
    platform::hide_bubble(&app, explicit);
    remember_bubble_size(&app);
}

/// The memo page received the quit request and is saving.
#[tauri::command]
pub fn quit_ack(app: AppHandle) {
    state(&app).quit.lock().unwrap().acknowledged = true;
}

/// The memo page saved everything after a quit request.
#[tauri::command]
pub fn quit_app(app: AppHandle) {
    app.exit(0);
}

/// Saving failed during quit: stay open so the text is not lost, and show
/// the memo with its error.
#[tauri::command]
pub fn quit_cancelled(app: AppHandle) {
    {
        let mut quit = state(&app).quit.lock().unwrap();
        quit.requested = false;
        quit.acknowledged = false;
    }
    if !platform::bubble_visible(&app) {
        open_bubble(&app);
    }
}

/// Windows character page: a click that was not a drag.
#[tauri::command]
pub fn character_clicked(app: AppHandle) {
    toggle_bubble(&app);
}

/// Windows character page: right click.
#[tauri::command]
pub fn character_menu(app: AppHandle) {
    platform::show_character_menu(&app);
}

/// Windows character page: which image to show.
#[tauri::command]
pub fn character_look(app: AppHandle) -> serde_json::Value {
    platform::character_look(&app)
}

// ---------- open / close ----------

pub fn toggle_bubble(app: &AppHandle) {
    if platform::bubble_visible(app) {
        request_close(app, true);
    } else {
        open_bubble(app);
    }
}

pub fn request_close(app: &AppHandle, explicit: bool) {
    let _ = app.emit_to(BUBBLE_LABEL, "memo:close-request", CloseRequest { explicit });
}

pub fn open_bubble(app: &AppHandle) {
    let frame = bubble_frame(app, None);
    platform::show_bubble(app, frame);
    let _ = app.emit_to(BUBBLE_LABEL, "memo:opened", ());
    // A click elsewhere during the first moments is ignored as a focus
    // glitch; check again once that window has passed.
    let handle = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(450));
        let handle2 = handle.clone();
        let _ = handle.run_on_main_thread(move || {
            if platform::bubble_visible(&handle2) && !platform::bubble_is_focused(&handle2) {
                request_close(&handle2, false);
            }
        });
    });
}

#[tauri::command]
pub fn open_memo(app: AppHandle) {
    if !platform::bubble_visible(&app) {
        open_bubble(&app);
    }
}

fn bubble_frame(app: &AppHandle, current_size: Option<(f64, f64)>) -> Rect {
    let character = platform::character_frame(app);
    let visible = platform::visible_frame_containing(app, character);
    let scale = platform::units_per_point(app);
    let (width, height) = current_size.unwrap_or_else(|| {
        let settings = state(app).settings.lock().unwrap();
        (settings.memo_width * scale, settings.memo_height * scale)
    });
    let placed = placement::bubble_placement(character, width, height, visible);
    Rect { x: placed.x, y: placed.y, width, height }
}

fn remember_bubble_size(app: &AppHandle) {
    let Some((width, height)) = platform::bubble_size(app) else { return };
    let scale = platform::units_per_point(app);
    {
        let mut settings = state(app).settings.lock().unwrap();
        settings.memo_width = (width / scale).clamp(MIN_MEMO_SIZE.0, MAX_MEMO_SIZE.0);
        settings.memo_height = (height / scale).clamp(MIN_MEMO_SIZE.1, MAX_MEMO_SIZE.1);
    }
    save_settings(app);
}

/// The character moved (dragged, resized or clamped). An open memo follows.
pub fn character_moved(app: &AppHandle, ended: bool) {
    if platform::bubble_visible(app) {
        let size = platform::bubble_size(app);
        platform::move_bubble(app, bubble_frame(app, size));
    }
    if ended {
        let frame = platform::character_frame(app);
        let visible = platform::visible_frame_containing(app, frame);
        let (x, y) = placement::clamped_origin(frame.x, frame.y, frame.width, frame.height, visible);
        if (x, y) != (frame.x, frame.y) {
            platform::set_character_origin(app, x, y);
            if platform::bubble_visible(app) {
                let size = platform::bubble_size(app);
                platform::move_bubble(app, bubble_frame(app, size));
            }
        }
        // Stored in platform frame units (points on macOS, physical pixels on
        // Windows) so mixed-scale monitors restore to the same place.
        state(app).settings.lock().unwrap().character_origin = Some((x, y));
        save_settings(app);
    }
}

pub fn on_window_event(window: &tauri::Window, event: &WindowEvent) {
    platform::on_window_event(window, event);
    if window.label() != BUBBLE_LABEL {
        return;
    }
    match event {
        // Another app or window took keyboard focus: keep that choice, save and close.
        WindowEvent::Focused(false) => {
            if platform::bubble_visible(window.app_handle()) && !platform::bubble_focus_expected(window.app_handle()) {
                request_close(window.app_handle(), false);
            }
        }
        WindowEvent::CloseRequested { api, .. } => {
            api.prevent_close();
            request_close(window.app_handle(), true);
        }
        _ => {}
    }
}

// ---------- character ----------

pub fn apply_character(app: &AppHandle) {
    let (choice, custom, size, origin) = {
        let settings = state(app).settings.lock().unwrap();
        let custom = settings.custom_character_file.as_ref().map(|name| state(app).data_dir.join(name));
        (settings.character_choice, custom, settings.character_size, settings.character_origin)
    };
    platform::set_character(app, choice, custom.as_deref(), size);
    let scale = platform::units_per_point(app);
    let side = size * scale;
    let (x, y) = match origin {
        Some((x, y)) => (x, y),
        None => {
            let visible = platform::primary_visible_frame(app);
            (visible.x + visible.width - side - 24.0 * scale, visible.y + visible.height - side - 24.0 * scale)
        }
    };
    let visible_frame = platform::visible_frame_containing(app, Rect { x, y, width: side, height: side });
    let (x, y) = placement::clamped_origin(x, y, side, side, visible_frame);
    platform::set_character_origin(app, x, y);
    platform::set_character_visible(app, true);
    rebuild_tray_menu(app);
}

fn choose_custom_character(app: &AppHandle) {
    let handle = app.clone();
    platform::activate_app(app);
    app.dialog()
        .file()
        .set_title(tr("캐릭터 이미지 선택", "Choose a Character Image"))
        .add_filter(tr("이미지", "Images"), &["gif", "png", "jpg", "jpeg", "webp"])
        .pick_file(move |picked| {
            let Some(path) = picked.and_then(|file| file.into_path().ok()) else { return };
            let handle2 = handle.clone();
            let _ = handle.run_on_main_thread(move || match import_custom_character(&handle2, &path) {
                Ok(()) => apply_character(&handle2),
                Err(message) => show_message(&handle2, tr("캐릭터를 바꾸지 못했습니다", "Could not use that character"), &message, true),
            });
        });
}

fn import_custom_character(app: &AppHandle, source: &Path) -> Result<(), String> {
    let metadata = std::fs::metadata(source).map_err(|error| error.to_string())?;
    if metadata.len() > MAX_CUSTOM_IMAGE_BYTES {
        return Err(tr("15MB보다 작은 이미지를 골라 주세요.", "Choose an image smaller than 15 MB.").to_owned());
    }
    let bytes = std::fs::read(source).map_err(|error| error.to_string())?;
    let extension = image_extension(&bytes)
        .ok_or_else(|| tr("GIF, PNG, JPEG, WebP 이미지만 쓸 수 있습니다.", "Use a GIF, PNG, JPEG or WebP image.").to_owned())?;
    if !platform::image_is_decodable(&bytes) {
        return Err(tr(
            "이 이미지는 쓸 수 없습니다. 읽을 수 없거나 너무 큽니다(한 장 1,600만 픽셀, 움직이는 그림은 240장·전체 2,400만 픽셀까지).",
            "That image can't be used: it could not be read, or it is too large (up to 16 megapixels, or 240 frames and 24 megapixels in all for an animation).",
        )
        .to_owned());
    }
    let state = state(app);
    let name = format!("custom-character.{extension}");
    debug_assert!(crate::settings::CUSTOM_CHARACTER_FILES.contains(&name.as_str()));
    let target = state.data_dir.join(&name);
    let temporary = state.data_dir.join(format!(".{name}.tmp"));
    std::fs::write(&temporary, &bytes).map_err(|error| error.to_string())?;
    std::fs::rename(&temporary, &target).map_err(|error| error.to_string())?;
    let mut settings = state.settings.lock().unwrap();
    if let Some(old) = settings.custom_character_file.replace(name.clone()) {
        if old != name {
            let _ = std::fs::remove_file(state.data_dir.join(old));
        }
    }
    settings.character_choice = CharacterChoice::Custom;
    drop(settings);
    save_settings(app);
    Ok(())
}

pub fn image_extension(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        Some("gif")
    } else if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some("png")
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("jpg")
    } else if bytes.len() > 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("webp")
    } else {
        None
    }
}

// ---------- menus ----------

/// Opened from the menus in the default browser (App Store guideline 5.1.1
/// wants the privacy policy reachable inside the app).
pub const PRIVACY_POLICY_URL: &str = "https://github.com/tinkerer0/MemoBuddy/blob/main/docs/PRIVACY.md";
/// The same notices ship inside the app as THIRD_PARTY_LICENSES.md.
pub const LICENSES_URL: &str = "https://github.com/tinkerer0/MemoBuddy/blob/main/THIRD_PARTY_LICENSES.md";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MenuAction {
    OpenMemo,
    Character(CharacterChoice),
    CustomCharacter,
    Size(usize),
    Theme(Theme),
    PrivacyPolicy,
    Licenses,
    Quit,
}

impl MenuAction {
    pub fn id(self) -> String {
        match self {
            MenuAction::OpenMemo => "open".into(),
            MenuAction::Character(choice) => format!("character-{}", choice.id()),
            MenuAction::CustomCharacter => "character-custom-pick".into(),
            MenuAction::Size(index) => format!("size-{index}"),
            MenuAction::Theme(theme) => format!("theme-{theme:?}"),
            MenuAction::PrivacyPolicy => "privacy".into(),
            MenuAction::Licenses => "licenses".into(),
            MenuAction::Quit => "quit".into(),
        }
    }

    pub fn all() -> Vec<MenuAction> {
        let mut all = vec![
            MenuAction::OpenMemo,
            MenuAction::CustomCharacter,
            MenuAction::Theme(Theme::Light),
            MenuAction::Theme(Theme::Dark),
            MenuAction::PrivacyPolicy,
            MenuAction::Licenses,
            MenuAction::Quit,
        ];
        all.push(MenuAction::Character(CharacterChoice::Classic));
        all.extend(characters::BUILT_IN.iter().map(|builtin| MenuAction::Character(CharacterChoice::Builtin(builtin))));
        all.push(MenuAction::Character(CharacterChoice::Custom));
        for index in 0..CHARACTER_SIZES.len() {
            all.push(MenuAction::Size(index));
        }
        all
    }

    pub fn from_id(id: &str) -> Option<MenuAction> {
        MenuAction::all().into_iter().find(|action| action.id() == id)
    }
}

pub enum MenuEntry {
    Item { action: MenuAction, title: String, checked: Option<bool>, enabled: bool },
    Separator,
    Submenu { title: String, items: Vec<MenuEntry> },
}

fn item(action: MenuAction, title: &str) -> MenuEntry {
    MenuEntry::Item { action, title: title.to_owned(), checked: None, enabled: true }
}

fn check(action: MenuAction, title: &str, checked: bool) -> MenuEntry {
    MenuEntry::Item { action, title: title.to_owned(), checked: Some(checked), enabled: true }
}

pub fn menu_model(app: &AppHandle, include_open: bool) -> Vec<MenuEntry> {
    let settings = state(app).settings.lock().unwrap().clone();
    let choice = settings.character_choice;
    let mut characters = vec![check(MenuAction::Character(CharacterChoice::Classic), "Classic", choice == CharacterChoice::Classic)];
    for builtin in characters::BUILT_IN {
        let builtin_choice = CharacterChoice::Builtin(builtin);
        characters.push(check(MenuAction::Character(builtin_choice), builtin.name, choice == builtin_choice));
    }
    if settings.custom_character_file.is_some() {
        characters.push(check(MenuAction::Character(CharacterChoice::Custom), tr("내 이미지", "My Image"), choice == CharacterChoice::Custom));
    }
    characters.push(MenuEntry::Separator);
    characters.push(item(MenuAction::CustomCharacter, tr("이미지 선택…", "Choose Image…")));
    let size_titles = [tr("작게", "Small"), tr("보통", "Medium"), tr("크게", "Large")];
    let sizes = CHARACTER_SIZES
        .iter()
        .enumerate()
        .map(|(index, size)| check(MenuAction::Size(index), size_titles[index], (settings.character_size - size).abs() < 0.5))
        .collect();
    let theme = settings.theme.unwrap_or(Theme::Light);
    let themes = vec![
        check(MenuAction::Theme(Theme::Light), tr("화이트", "White"), theme == Theme::Light),
        check(MenuAction::Theme(Theme::Dark), tr("다크", "Dark"), theme == Theme::Dark),
    ];

    let mut model = Vec::new();
    if include_open {
        model.push(item(MenuAction::OpenMemo, tr("메모 열기", "Open Memo")));
        model.push(MenuEntry::Separator);
    }
    model.push(MenuEntry::Submenu { title: tr("캐릭터", "Character").to_owned(), items: characters });
    model.push(MenuEntry::Submenu { title: tr("크기", "Size").to_owned(), items: sizes });
    model.push(MenuEntry::Submenu { title: tr("테마", "Theme").to_owned(), items: themes });
    model.push(MenuEntry::Separator);
    model.push(item(MenuAction::PrivacyPolicy, tr("개인정보 처리방침", "Privacy Policy")));
    model.push(item(MenuAction::Licenses, tr("오픈소스 라이선스", "Open-Source Licenses")));
    model.push(MenuEntry::Separator);
    model.push(item(MenuAction::Quit, tr("MemoBuddy 종료", "Quit MemoBuddy")));
    model
}

pub fn handle_menu_action(app: &AppHandle, action: MenuAction) {
    match action {
        MenuAction::OpenMemo => {
            if !platform::bubble_visible(app) {
                open_bubble(app);
            }
        }
        MenuAction::Character(choice) => {
            {
                let mut settings = state(app).settings.lock().unwrap();
                if choice == CharacterChoice::Custom && settings.custom_character_file.is_none() {
                    return;
                }
                settings.character_choice = choice;
            }
            save_settings(app);
            apply_character(app);
        }
        MenuAction::CustomCharacter => choose_custom_character(app),
        MenuAction::Size(index) => {
            state(app).settings.lock().unwrap().character_size = CHARACTER_SIZES[index.min(CHARACTER_SIZES.len() - 1)];
            save_settings(app);
            apply_character(app);
            character_moved(app, true);
        }
        MenuAction::Theme(theme) => {
            state(app).settings.lock().unwrap().theme = Some(theme);
            save_settings(app);
            apply_theme(app);
            rebuild_tray_menu(app);
        }
        MenuAction::PrivacyPolicy => open_link(app, PRIVACY_POLICY_URL),
        MenuAction::Licenses => open_link(app, LICENSES_URL),
        MenuAction::Quit => request_quit(app),
    }
}

/// Opens a page in the default browser; if that fails, shows the address so
/// it can still be read (no browser, or opening was refused).
fn open_link(app: &AppHandle, url: &str) {
    if !platform::open_url(app, url) {
        let message = format!("{}\n{url}", tr("브라우저를 열 수 없습니다. 이 주소를 브라우저에 붙여 넣어 주세요.", "The browser could not be opened. Paste this address into a browser:"));
        show_message(app, tr("페이지를 열 수 없습니다", "Could not open the page"), &message, false);
    }
}

/// Ask the memo page to save everything and quit. If the page never answers
/// (it crashed or hung), quit after 3 s: everything it had already saved is
/// on disk. Once it answers, only the page decides (a failed save cancels).
/// Returns true when a save-then-quit round was started (the caller should
/// hold the exit); false when one is already running.
/// Returns whether the exit must wait for the memo page to save.
pub fn begin_quit(app: &AppHandle) -> bool {
    // Startup failed before the state existed (a message is showing): just quit.
    if app.try_state::<AppState>().is_none() {
        return false;
    }
    // A repeated request while the page is still saving must wait too. The page
    // calls quit_app when it is done; the 3 s timer exits if it never answers.
    request_quit(app);
    true
}

pub fn request_quit(app: &AppHandle) {
    {
        let mut quit = state(app).quit.lock().unwrap();
        if quit.requested {
            return;
        }
        quit.serial += 1;
        quit.requested = true;
        quit.acknowledged = false;
    }
    let serial = state(app).quit.lock().unwrap().serial;
    let _ = app.emit_to(BUBBLE_LABEL, "memo:quit-request", ());
    let handle = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(3));
        let unanswered = {
            let quit = state(&handle).quit.lock().unwrap();
            quit.serial == serial && quit.requested && !quit.acknowledged
        };
        if unanswered {
            handle.exit(0);
        }
    });
}

fn build_tauri_menu(app: &AppHandle, entries: &[MenuEntry]) -> tauri::Result<Vec<Box<dyn tauri::menu::IsMenuItem<tauri::Wry>>>> {
    let mut built: Vec<Box<dyn tauri::menu::IsMenuItem<tauri::Wry>>> = Vec::new();
    for entry in entries {
        match entry {
            MenuEntry::Item { action, title, checked: Some(checked), enabled } => {
                built.push(Box::new(CheckMenuItem::with_id(app, action.id(), title, *enabled, *checked, None::<&str>)?));
            }
            MenuEntry::Item { action, title, checked: None, enabled } => {
                built.push(Box::new(MenuItem::with_id(app, action.id(), title, *enabled, None::<&str>)?));
            }
            MenuEntry::Separator => built.push(Box::new(PredefinedMenuItem::separator(app)?)),
            MenuEntry::Submenu { title, items } => {
                let children = build_tauri_menu(app, items)?;
                let refs: Vec<&dyn tauri::menu::IsMenuItem<tauri::Wry>> = children.iter().map(|child| child.as_ref()).collect();
                built.push(Box::new(Submenu::with_items(app, title, true, &refs)?));
            }
        }
    }
    Ok(built)
}

pub fn tauri_menu(app: &AppHandle, include_open: bool) -> tauri::Result<Menu<tauri::Wry>> {
    let items = build_tauri_menu(app, &menu_model(app, include_open))?;
    let refs: Vec<&dyn tauri::menu::IsMenuItem<tauri::Wry>> = items.iter().map(|item| item.as_ref()).collect();
    Menu::with_items(app, &refs)
}

fn install_tray(app: &AppHandle) -> tauri::Result<()> {
    let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray-template.png"))?;
    let tray = TrayIconBuilder::with_id("memopet-tray")
        .icon(icon)
        .icon_as_template(true)
        .tooltip("MemoBuddy")
        .menu(&tauri_menu(app, true)?)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| {
            if let Some(action) = MenuAction::from_id(event.id().as_ref()) {
                handle_menu_action(app, action);
            }
        })
        .build(app)?;
    *state(app).tray.lock().unwrap() = Some(tray);
    Ok(())
}

/// Replaces Tauri's default macOS app menu. Its Quit (⌘Q) calls `terminate:`,
/// which exits without the memo page saving. This Quit goes through the same
/// save-then-quit path as the tray (same id). The Edit items stay because
/// they give the memo its text shortcuts (⌘C, ⌘V, ⌘A, text undo).
#[cfg(target_os = "macos")]
fn install_app_menu(app: &AppHandle) -> tauri::Result<()> {
    let quit = MenuItem::with_id(app, MenuAction::Quit.id(), tr("MemoBuddy 종료", "Quit MemoBuddy"), true, Some("CmdOrCtrl+Q"))?;
    let app_menu = Submenu::with_items(app, "MemoBuddy", true, &[&quit])?;
    let edit = Submenu::with_items(
        app,
        tr("편집", "Edit"),
        true,
        &[
            &PredefinedMenuItem::undo(app, Some(tr("실행 취소", "Undo")))?,
            &PredefinedMenuItem::redo(app, Some(tr("실행 복귀", "Redo")))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, Some(tr("오려두기", "Cut")))?,
            &PredefinedMenuItem::copy(app, Some(tr("복사하기", "Copy")))?,
            &PredefinedMenuItem::paste(app, Some(tr("붙여넣기", "Paste")))?,
            &PredefinedMenuItem::select_all(app, Some(tr("전체 선택", "Select All")))?,
        ],
    )?;
    app.set_menu(Menu::with_items(app, &[&app_menu, &edit])?)?;
    Ok(())
}

pub fn rebuild_tray_menu(app: &AppHandle) {
    let tray = state(app).tray.lock().unwrap().clone();
    if let (Some(tray), Ok(menu)) = (tray, tauri_menu(app, true)) {
        let _ = tray.set_menu(Some(menu));
    }
}

pub fn show_message(app: &AppHandle, title: &str, message: &str, warning: bool) {
    platform::activate_app(app);
    app.dialog()
        .message(message)
        .title(title)
        .kind(if warning { MessageDialogKind::Warning } else { MessageDialogKind::Info })
        .show(|_| {});
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disk_full_has_its_own_message() {
        use crate::core::store::StoreError;
        #[cfg(unix)]
        let full = std::io::Error::from_raw_os_error(28); // ENOSPC
        #[cfg(windows)]
        let full = std::io::Error::from_raw_os_error(112); // ERROR_DISK_FULL
        let message = save_error_message(&StoreError::Io(full));
        assert!(message.contains("디스크 공간이 부족합니다") || message.contains("The disk is full"), "{message}");
    }

    #[test]
    fn image_extension_uses_magic_bytes() {
        assert_eq!(image_extension(b"GIF89a...."), Some("gif"));
        assert_eq!(image_extension(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0]), Some("png"));
        assert_eq!(image_extension(&[0xFF, 0xD8, 0xFF, 0xE0]), Some("jpg"));
        assert_eq!(image_extension(b"RIFF\0\0\0\0WEBPVP8 "), Some("webp"));
        assert_eq!(image_extension(b"<svg"), None);
    }

    #[test]
    fn menu_ids_round_trip() {
        for action in MenuAction::all() {
            assert_eq!(MenuAction::from_id(&action.id()), Some(action));
        }
    }
}
