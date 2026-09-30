//! Windows windows. Frames are physical pixels in virtual-screen coordinates
//! (what Tauri's Physical* positions use), so monitors with different scale
//! factors line up without conversion.

use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use base64::Engine;
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowEvent};
use windows_sys::Win32::Foundation::HWND;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    GetForegroundWindow, GetWindowLongPtrW, IsWindow, SetForegroundWindow, SetWindowLongPtrW, SystemParametersInfoW, GWL_EXSTYLE,
    SPI_GETCLIENTAREAANIMATION, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

use crate::app::{self, BUBBLE_LABEL, CHARACTER_LABEL};
use crate::core::placement::Rect;
use crate::settings::{CharacterChoice, Settings, Theme, MAX_MEMO_SIZE, MIN_MEMO_SIZE};

static BUBBLE_SHOWN: AtomicBool = AtomicBool::new(false);
static PREVIOUS_FOREGROUND: AtomicIsize = AtomicIsize::new(0);
static MOVE_SERIAL: AtomicU64 = AtomicU64::new(0);
static IGNORE_BLUR_UNTIL: Mutex<Option<Instant>> = Mutex::new(None);
static LOOK: Mutex<Option<Look>> = Mutex::new(None);

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Look {
    kind: &'static str,
    source: Option<String>,
    animate: bool,
}

fn window(app: &AppHandle, label: &str) -> Option<WebviewWindow> {
    app.get_webview_window(label)
}

fn rect_of(window: &WebviewWindow) -> Option<Rect> {
    let position = window.outer_position().ok()?;
    let size = window.outer_size().ok()?;
    Some(Rect { x: position.x as f64, y: position.y as f64, width: size.width as f64, height: size.height as f64 })
}

pub fn units_per_point(app: &AppHandle) -> f64 {
    window(app, CHARACTER_LABEL).and_then(|w| w.scale_factor().ok()).unwrap_or(1.0)
}

fn monitors(app: &AppHandle) -> Vec<(Rect, Rect)> {
    app.available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|monitor| {
            let frame = Rect {
                x: monitor.position().x as f64,
                y: monitor.position().y as f64,
                width: monitor.size().width as f64,
                height: monitor.size().height as f64,
            };
            let area = monitor.work_area();
            let visible = Rect {
                x: area.position.x as f64,
                y: area.position.y as f64,
                width: area.size.width as f64,
                height: area.size.height as f64,
            };
            (frame, visible)
        })
        .collect()
}

fn intersection_area(a: Rect, b: Rect) -> f64 {
    let width = (a.x + a.width).min(b.x + b.width) - a.x.max(b.x);
    let height = (a.y + a.height).min(b.y + b.height) - a.y.max(b.y);
    if width > 0.0 && height > 0.0 { width * height } else { 0.0 }
}

fn distance_squared(rect: Rect, x: f64, y: f64) -> f64 {
    let dx = (rect.x - x).max(0.0).max(x - (rect.x + rect.width));
    let dy = (rect.y - y).max(0.0).max(y - (rect.y + rect.height));
    dx * dx + dy * dy
}

const FALLBACK: Rect = Rect { x: 0.0, y: 0.0, width: 1280.0, height: 720.0 };

pub fn visible_frame_containing(app: &AppHandle, rect: Rect) -> Rect {
    let screens = monitors(app);
    if let Some((_, visible)) = screens
        .iter()
        .filter(|(frame, _)| intersection_area(*frame, rect) > 0.0)
        .max_by(|a, b| intersection_area(a.0, rect).total_cmp(&intersection_area(b.0, rect)))
    {
        return *visible;
    }
    let (cx, cy) = (rect.x + rect.width / 2.0, rect.y + rect.height / 2.0);
    screens
        .iter()
        .min_by(|a, b| distance_squared(a.0, cx, cy).total_cmp(&distance_squared(b.0, cx, cy)))
        .map(|(_, visible)| *visible)
        .unwrap_or(FALLBACK)
}

pub fn primary_visible_frame(app: &AppHandle) -> Rect {
    app.primary_monitor()
        .ok()
        .flatten()
        .map(|monitor| {
            let area = monitor.work_area();
            Rect { x: area.position.x as f64, y: area.position.y as f64, width: area.size.width as f64, height: area.size.height as f64 }
        })
        .unwrap_or(FALLBACK)
}

fn animations_enabled() -> bool {
    let mut enabled: i32 = 1;
    let ok = unsafe { SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &mut enabled as *mut i32 as *mut _, 0) };
    ok == 0 || enabled != 0
}

fn add_ex_style(window: &WebviewWindow, flags: u32) {
    if let Ok(hwnd) = window.hwnd() {
        let hwnd = hwnd.0 as HWND;
        unsafe {
            let style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style | flags as isize);
        }
    }
}

pub fn setup(app: &AppHandle, settings: &Settings) -> Result<(), String> {
    let character = WebviewWindowBuilder::new(app, CHARACTER_LABEL, WebviewUrl::App("character.html".into()))
        .title("MemoPet")
        .transparent(true)
        .decorations(false)
        .shadow(false)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .focusable(false)
        .visible(false)
        .inner_size(settings.character_size, settings.character_size)
        .build()
        .map_err(|error| error.to_string())?;
    // Never take focus from the app being used, and stay out of Alt+Tab.
    add_ex_style(&character, WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);

    let bubble = WebviewWindowBuilder::new(app, BUBBLE_LABEL, WebviewUrl::App("bubble.html".into()))
        .title("MemoPet")
        .decorations(false)
        .shadow(true)
        .resizable(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        .inner_size(settings.memo_width, settings.memo_height)
        .min_inner_size(MIN_MEMO_SIZE.0, MIN_MEMO_SIZE.1)
        .max_inner_size(MAX_MEMO_SIZE.0, MAX_MEMO_SIZE.1)
        .build()
        .map_err(|error| error.to_string())?;
    add_ex_style(&bubble, WS_EX_TOOLWINDOW);
    Ok(())
}

/// Character window moves come from the OS drag; report the end once the
/// window has been still for a moment.
pub fn on_window_event(window: &tauri::Window, event: &WindowEvent) {
    if window.label() != CHARACTER_LABEL {
        return;
    }
    if let WindowEvent::Moved(_) = event {
        let app = window.app_handle().clone();
        app::character_moved(&app, false);
        let serial = MOVE_SERIAL.fetch_add(1, Ordering::SeqCst) + 1;
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(250));
            if MOVE_SERIAL.load(Ordering::SeqCst) == serial {
                let handle = app.clone();
                let _ = app.run_on_main_thread(move || app::character_moved(&handle, true));
            }
        });
    }
}

pub fn character_frame(app: &AppHandle) -> Rect {
    window(app, CHARACTER_LABEL).and_then(|w| rect_of(&w)).unwrap_or(Rect { x: 0.0, y: 0.0, width: 80.0, height: 80.0 })
}

pub fn set_character_origin(app: &AppHandle, x: f64, y: f64) {
    if let Some(w) = window(app, CHARACTER_LABEL) {
        let _ = w.set_position(PhysicalPosition::new(x.round() as i32, y.round() as i32));
    }
}

pub fn set_character_visible(app: &AppHandle, visible: bool) {
    if let Some(w) = window(app, CHARACTER_LABEL) {
        let _ = if visible { w.show() } else { w.hide() };
    }
}

pub fn set_character(app: &AppHandle, choice: CharacterChoice, custom: Option<&Path>, size: f64) {
    let Some(w) = window(app, CHARACTER_LABEL) else { return };
    let scale = w.scale_factor().unwrap_or(1.0);
    let side = (size * scale).round() as u32;
    if let Some(frame) = rect_of(&w) {
        let _ = w.set_size(PhysicalSize::new(side, side));
        let _ = w.set_position(PhysicalPosition::new(frame.x as i32, frame.y as i32));
    }
    let source = match choice {
        CharacterChoice::Classic => None,
        CharacterChoice::MemoWriter => Some("/default-character.gif".to_owned()),
        CharacterChoice::OrbitingPlanet => Some("/orbiting-planet.gif".to_owned()),
        CharacterChoice::Custom => custom.and_then(|path| std::fs::read(path).ok()).map(|bytes| {
            let mime = match app::image_extension(&bytes) {
                Some("gif") => "image/gif",
                Some("png") => "image/png",
                Some("webp") => "image/webp",
                _ => "image/jpeg",
            };
            format!("data:{mime};base64,{}", base64::engine::general_purpose::STANDARD.encode(bytes))
        }),
    };
    let look = Look { kind: if source.is_some() { "image" } else { "classic" }, source, animate: animations_enabled() };
    *LOOK.lock().unwrap() = Some(look.clone());
    let _ = app.emit_to(CHARACTER_LABEL, "character:look", look);
}

pub fn character_look(_app: &AppHandle) -> serde_json::Value {
    serde_json::to_value(LOOK.lock().unwrap().clone().unwrap_or(Look { kind: "classic", source: None, animate: true })).unwrap_or_default()
}

pub fn show_character_menu(app: &AppHandle) {
    if let (Some(w), Ok(menu)) = (window(app, CHARACTER_LABEL), app::tauri_menu(app, true)) {
        let _ = w.popup_menu(&menu);
    }
}

/// Decodes the first frame so a file with only a valid header is rejected.
/// macOS needs this before a dialog; Windows brings the dialog forward itself.
pub fn activate_app(_app: &AppHandle) {}

pub fn image_is_decodable(bytes: &[u8]) -> bool {
    app::image_extension(bytes).is_some()
        && image::load_from_memory(bytes).is_ok_and(|image| image.width() > 0 && image.height() > 0)
}

pub fn bubble_visible(_app: &AppHandle) -> bool {
    BUBBLE_SHOWN.load(Ordering::SeqCst)
}

pub fn bubble_focus_expected(_app: &AppHandle) -> bool {
    IGNORE_BLUR_UNTIL.lock().unwrap().is_some_and(|until| Instant::now() < until)
}

pub fn bubble_is_focused(app: &AppHandle) -> bool {
    window(app, BUBBLE_LABEL).and_then(|w| w.is_focused().ok()).unwrap_or(false)
}

pub fn bubble_size(app: &AppHandle) -> Option<(f64, f64)> {
    window(app, BUBBLE_LABEL).and_then(|w| rect_of(&w)).map(|rect| (rect.width, rect.height))
}

pub fn show_bubble(app: &AppHandle, frame: Rect) {
    let Some(w) = window(app, BUBBLE_LABEL) else { return };
    let foreground = unsafe { GetForegroundWindow() } as isize;
    let own = [BUBBLE_LABEL, CHARACTER_LABEL].iter().filter_map(|label| window(app, label)?.hwnd().ok()).any(|hwnd| hwnd.0 as isize == foreground);
    PREVIOUS_FOREGROUND.store(if own { 0 } else { foreground }, Ordering::SeqCst);
    *IGNORE_BLUR_UNTIL.lock().unwrap() = Some(Instant::now() + Duration::from_millis(400));
    move_bubble(app, frame);
    BUBBLE_SHOWN.store(true, Ordering::SeqCst);
    let _ = w.show();
    let _ = w.set_focus();
}

pub fn move_bubble(app: &AppHandle, frame: Rect) {
    if let Some(w) = window(app, BUBBLE_LABEL) {
        let _ = w.set_size(PhysicalSize::new(frame.width.round() as u32, frame.height.round() as u32));
        let _ = w.set_position(PhysicalPosition::new(frame.x.round() as i32, frame.y.round() as i32));
    }
}

/// Explicit closes (Esc, clicking the character) try to give focus back to
/// the window that was in front; Windows may refuse, which is fine.
pub fn hide_bubble(app: &AppHandle, explicit: bool) {
    BUBBLE_SHOWN.store(false, Ordering::SeqCst);
    if let Some(w) = window(app, BUBBLE_LABEL) {
        let _ = w.hide();
    }
    let previous = PREVIOUS_FOREGROUND.swap(0, Ordering::SeqCst);
    if explicit && previous != 0 {
        unsafe {
            let hwnd = previous as HWND;
            if IsWindow(hwnd) != 0 {
                SetForegroundWindow(hwnd);
            }
        }
    }
}

pub fn system_theme(app: &AppHandle) -> Theme {
    match window(app, CHARACTER_LABEL).and_then(|w| w.theme().ok()) {
        Some(tauri::Theme::Dark) => Theme::Dark,
        _ => Theme::Light,
    }
}

/// Window chrome follows `set_theme`; the pages also get the theme through
/// `ui_info` and the `memo:theme` event and style themselves from it.
pub fn set_theme(app: &AppHandle, theme: Theme) {
    let value = match theme {
        Theme::Light => tauri::Theme::Light,
        Theme::Dark => tauri::Theme::Dark,
    };
    for label in [CHARACTER_LABEL, BUBBLE_LABEL] {
        if let Some(w) = window(app, label) {
            let _ = w.set_theme(Some(value));
        }
    }
}
