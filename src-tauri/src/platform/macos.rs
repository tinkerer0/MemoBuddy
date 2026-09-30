//! macOS windows. Frames are in points with a top-left origin at the top of
//! the primary screen (y grows down), converted from AppKit's bottom-left
//! coordinates here and nowhere else.

use std::cell::{Cell, RefCell};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::{define_class, msg_send, sel, AllocAnyThread, DefinedClass, MainThreadMarker, MainThreadOnly};
use objc2_app_kit::{
    NSAppearance, NSAppearanceCustomization, NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSApplication, NSApplicationActivationOptions,
    NSBackingStoreType, NSBezierPath, NSBitmapImageRep, NSColor, NSControlStateValueOff, NSControlStateValueOn, NSEvent, NSImage,
    NSImageCurrentFrame, NSImageCurrentFrameDuration, NSImageFrameCount, NSMenu, NSMenuItem, NSPanel, NSRunningApplication, NSScreen, NSView,
    NSWindow, NSWindowCollectionBehavior, NSWindowStyleMask, NSWorkspace,
};
use objc2_foundation::{NSArray, NSData, NSMutableArray, NSNumber, NSPoint, NSRect, NSSize, NSString};
use objc2_quartz_core::{kCAAnimationDiscrete, kCAGravityResizeAspect, CAKeyframeAnimation, CALayer, CAMediaTiming};
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

use crate::app::{self, MenuAction, MenuEntry, BUBBLE_LABEL};
use crate::core::placement::Rect;
use crate::settings::{CharacterChoice, Settings, Theme, MAX_MEMO_SIZE, MIN_MEMO_SIZE};

static APP: OnceLock<AppHandle> = OnceLock::new();
static BUBBLE_SHOWN: AtomicBool = AtomicBool::new(false);

thread_local! {
    static CHARACTER: RefCell<Option<(Retained<NSPanel>, Retained<CharacterView>)>> = const { RefCell::new(None) };
    static IGNORE_BLUR_UNTIL: Cell<Option<Instant>> = const { Cell::new(None) };
    /// The app that was in front when the memo opened; explicit closes return to it.
    static PREVIOUS_APP: RefCell<Option<Retained<NSRunningApplication>>> = const { RefCell::new(None) };
}

fn mtm() -> MainThreadMarker {
    MainThreadMarker::new().expect("MemoPet window code must run on the main thread")
}

// ---------- coordinates ----------

fn primary_height(mtm: MainThreadMarker) -> f64 {
    NSScreen::screens(mtm).firstObject().map(|screen| screen.frame().size.height).unwrap_or(0.0)
}

fn to_top_left(rect: NSRect, mtm: MainThreadMarker) -> Rect {
    Rect {
        x: rect.origin.x,
        y: primary_height(mtm) - rect.origin.y - rect.size.height,
        width: rect.size.width,
        height: rect.size.height,
    }
}

fn to_appkit(rect: Rect, mtm: MainThreadMarker) -> NSRect {
    NSRect::new(
        NSPoint::new(rect.x, primary_height(mtm) - rect.y - rect.height),
        NSSize::new(rect.width, rect.height),
    )
}

pub fn units_per_point(_app: &AppHandle) -> f64 {
    1.0
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

/// Visible frame (without menu bar and Dock) of the screen that shows most
/// of `rect`, or the nearest screen when it is off every screen.
pub fn visible_frame_containing(_app: &AppHandle, rect: Rect) -> Rect {
    let mtm = mtm();
    let screens: Vec<(Rect, Rect)> = NSScreen::screens(mtm)
        .iter()
        .map(|screen| (to_top_left(screen.frame(), mtm), to_top_left(screen.visibleFrame(), mtm)))
        .collect();
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
        .unwrap_or(Rect { x: 0.0, y: 0.0, width: 1440.0, height: 900.0 })
}

pub fn primary_visible_frame(_app: &AppHandle) -> Rect {
    let mtm = mtm();
    NSScreen::screens(mtm)
        .firstObject()
        .map(|screen| to_top_left(screen.visibleFrame(), mtm))
        .unwrap_or(Rect { x: 0.0, y: 0.0, width: 1440.0, height: 900.0 })
}

fn reduce_motion() -> bool {
    NSWorkspace::sharedWorkspace().accessibilityDisplayShouldReduceMotion()
}

// ---------- character view ----------

pub struct CharacterIvars {
    down_mouse: Cell<NSPoint>,
    down_origin: Cell<NSPoint>,
    pressed: Cell<bool>,
    dragging: Cell<bool>,
    draws_classic: Cell<bool>,
    /// Sublayer that shows image characters (frames animated by Core
    /// Animation, so playback costs the app almost no CPU).
    image_layer: RefCell<Option<Retained<CALayer>>>,
}

define_class!(
    // SAFETY: NSView has no subclassing requirements; CharacterView does not implement Drop.
    #[unsafe(super(NSView))]
    #[thread_kind = MainThreadOnly]
    #[name = "MemoPetCharacterView"]
    #[ivars = CharacterIvars]
    pub struct CharacterView;

    impl CharacterView {
        #[unsafe(method(acceptsFirstMouse:))]
        fn accepts_first_mouse(&self, _event: Option<&NSEvent>) -> bool {
            true
        }

        #[unsafe(method(mouseDown:))]
        fn mouse_down(&self, event: &NSEvent) {
            let ivars = self.ivars();
            ivars.down_mouse.set(screen_location(self, event));
            if let Some(window) = self.window() {
                ivars.down_origin.set(window.frame().origin);
            }
            ivars.pressed.set(true);
            ivars.dragging.set(false);
        }

        #[unsafe(method(mouseDragged:))]
        fn mouse_dragged(&self, event: &NSEvent) {
            let ivars = self.ivars();
            if !ivars.pressed.get() {
                return;
            }
            let now = screen_location(self, event);
            let start = ivars.down_mouse.get();
            let (dx, dy) = (now.x - start.x, now.y - start.y);
            if !ivars.dragging.get() && dx.hypot(dy) < 4.0 {
                return;
            }
            ivars.dragging.set(true);
            if let Some(window) = self.window() {
                let origin = ivars.down_origin.get();
                window.setFrameOrigin(NSPoint::new(origin.x + dx, origin.y + dy));
            }
            if let Some(app) = APP.get() {
                app::character_moved(app, false);
            }
        }

        #[unsafe(method(mouseUp:))]
        fn mouse_up(&self, _event: &NSEvent) {
            let ivars = self.ivars();
            if !ivars.pressed.replace(false) {
                return;
            }
            let Some(app) = APP.get() else { return };
            if ivars.dragging.replace(false) {
                app::character_moved(app, true);
            } else {
                app::toggle_bubble(app);
            }
        }

        #[unsafe(method(rightMouseDown:))]
        fn right_mouse_down(&self, event: &NSEvent) {
            let Some(app) = APP.get() else { return };
            let menu = build_ns_menu(self, &app::menu_model(app, true));
            NSMenu::popUpContextMenu_withEvent_forView(&menu, event, self);
        }

        #[unsafe(method(memoPetMenuAction:))]
        fn menu_action(&self, sender: &NSMenuItem) {
            let Some(app) = APP.get() else { return };
            let id = sender.representedObject().and_then(|object| object.downcast::<NSString>().ok()).map(|value| value.to_string());
            if let Some(action) = id.as_deref().and_then(MenuAction::from_id) {
                app::handle_menu_action(app, action);
            }
        }

        #[unsafe(method(drawRect:))]
        fn draw_rect(&self, _dirty: NSRect) {
            if self.ivars().draws_classic.get() {
                draw_classic(self);
            }
        }

        #[unsafe(method(viewDidChangeEffectiveAppearance))]
        fn appearance_changed(&self) {
            self.setNeedsDisplay(true);
        }

        #[unsafe(method(isAccessibilityElement))]
        fn is_accessibility_element(&self) -> bool {
            true
        }

        #[unsafe(method_id(accessibilityRole))]
        fn accessibility_role(&self) -> Retained<NSString> {
            NSString::from_str("AXButton")
        }

        #[unsafe(method_id(accessibilityLabel))]
        fn accessibility_label(&self) -> Retained<NSString> {
            NSString::from_str(crate::i18n::tr("MemoPet 메모 열기", "Open MemoPet memo"))
        }

        #[unsafe(method(accessibilityPerformPress))]
        fn accessibility_perform_press(&self) -> bool {
            if let Some(app) = APP.get() {
                app::toggle_bubble(app);
            }
            true
        }
    }
);

impl CharacterView {
    fn new(mtm: MainThreadMarker, frame: NSRect) -> Retained<Self> {
        let this = Self::alloc(mtm).set_ivars(CharacterIvars {
            down_mouse: Cell::new(NSPoint::new(0.0, 0.0)),
            down_origin: Cell::new(NSPoint::new(0.0, 0.0)),
            pressed: Cell::new(false),
            dragging: Cell::new(false),
            draws_classic: Cell::new(false),
            image_layer: RefCell::new(None),
        });
        unsafe { msg_send![super(this), initWithFrame: frame] }
    }
}

/// The event's position in screen coordinates (the window may be moving).
fn screen_location(view: &CharacterView, event: &NSEvent) -> NSPoint {
    match view.window() {
        Some(window) => {
            let local = event.locationInWindow();
            let origin = window.frame().origin;
            NSPoint::new(origin.x + local.x, origin.y + local.y)
        }
        None => NSEvent::mouseLocation(),
    }
}

fn draw_classic(view: &CharacterView) {
    let bounds = view.bounds();
    let names = NSArray::from_slice(&[unsafe { NSAppearanceNameDarkAqua }, unsafe { NSAppearanceNameAqua }]);
    let dark = view
        .effectiveAppearance()
        .bestMatchFromAppearancesWithNames(&names)
        .is_some_and(|name| name.to_string() == unsafe { NSAppearanceNameDarkAqua }.to_string());
    let (background, foreground) = if dark { (NSColor::whiteColor(), NSColor::blackColor()) } else { (NSColor::blackColor(), NSColor::whiteColor()) };
    let circle = NSRect::new(NSPoint::new(bounds.origin.x + 5.0, bounds.origin.y + 5.0), NSSize::new(bounds.size.width - 10.0, bounds.size.height - 10.0));
    background.setFill();
    NSBezierPath::bezierPathWithOvalInRect(circle).fill();
    let icon_width = bounds.size.width.min(bounds.size.height) * 0.28;
    let icon_height = icon_width * 1.18;
    let icon = NSRect::new(
        NSPoint::new(bounds.size.width / 2.0 - icon_width / 2.0, bounds.size.height / 2.0 - icon_height / 2.0),
        NSSize::new(icon_width, icon_height),
    );
    foreground.setStroke();
    let outline = NSBezierPath::bezierPathWithRoundedRect_xRadius_yRadius(icon, 2.5, 2.5);
    outline.setLineWidth(2.0);
    outline.stroke();
    for offset in [0.68, 0.5, 0.32] {
        let line = NSBezierPath::bezierPath();
        let y = icon.origin.y + icon.size.height * offset;
        line.moveToPoint(NSPoint::new(icon.origin.x + 4.0, y));
        line.lineToPoint(NSPoint::new(icon.origin.x + icon.size.width - 4.0, y));
        line.setLineWidth(1.5);
        line.stroke();
    }
}

fn build_ns_menu(target: &CharacterView, entries: &[MenuEntry]) -> Retained<NSMenu> {
    let mtm = mtm();
    let menu = NSMenu::new(mtm);
    menu.setAutoenablesItems(false);
    for entry in entries {
        match entry {
            MenuEntry::Separator => menu.addItem(&NSMenuItem::separatorItem(mtm)),
            MenuEntry::Item { action, title, checked, enabled } => {
                let item = unsafe {
                    NSMenuItem::initWithTitle_action_keyEquivalent(
                        NSMenuItem::alloc(mtm),
                        &NSString::from_str(title),
                        Some(sel!(memoPetMenuAction:)),
                        &NSString::from_str(""),
                    )
                };
                unsafe { item.setTarget(Some(target)) };
                let id = NSString::from_str(&action.id());
                unsafe { item.setRepresentedObject(Some(&id)) };
                item.setEnabled(*enabled);
                if let Some(checked) = checked {
                    item.setState(if *checked { NSControlStateValueOn } else { NSControlStateValueOff });
                }
                menu.addItem(&item);
            }
            MenuEntry::Submenu { title, items } => {
                let parent = unsafe {
                    NSMenuItem::initWithTitle_action_keyEquivalent(NSMenuItem::alloc(mtm), &NSString::from_str(title), None, &NSString::from_str(""))
                };
                let submenu = build_ns_menu(target, items);
                submenu.setTitle(&NSString::from_str(title));
                parent.setSubmenu(Some(&submenu));
                menu.addItem(&parent);
            }
        }
    }
    menu
}

// ---------- setup ----------

pub fn setup(app: &AppHandle, settings: &Settings) -> Result<(), String> {
    let _ = APP.set(app.clone());
    let mtm = mtm();

    // Character: native, transparent, never key, on every Space.
    let side = settings.character_size;
    let frame = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(side, side));
    let panel = {
        NSPanel::initWithContentRect_styleMask_backing_defer(
            NSPanel::alloc(mtm),
            frame,
            NSWindowStyleMask::Borderless | NSWindowStyleMask::NonactivatingPanel,
            NSBackingStoreType::Buffered,
            false,
        )
    };
    unsafe { panel.setReleasedWhenClosed(false) };
    panel.setOpaque(false);
    panel.setBackgroundColor(Some(&NSColor::clearColor()));
    panel.setHasShadow(false);
    panel.setLevel(3); // NSFloatingWindowLevel
    panel.setHidesOnDeactivate(false);
    panel.setFloatingPanel(true);
    panel.setBecomesKeyOnlyIfNeeded(true);
    panel.setCollectionBehavior(
        NSWindowCollectionBehavior::CanJoinAllSpaces | NSWindowCollectionBehavior::FullScreenAuxiliary | NSWindowCollectionBehavior::Stationary | NSWindowCollectionBehavior::IgnoresCycle,
    );
    let view = CharacterView::new(mtm, frame);
    panel.setContentView(Some(&view));
    CHARACTER.with(|cell| *cell.borrow_mut() = Some((panel, view)));

    // Memo: an ordinary Tauri window made transparent with public NSWindow
    // properties. Opening it activates MemoPet (like the Swift app); explicit
    // closes hand focus back to the app that was in front.
    let window = WebviewWindowBuilder::new(app, BUBBLE_LABEL, WebviewUrl::App("bubble.html".into()))
        .title("MemoPet")
        .decorations(false)
        .resizable(true)
        .visible(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(true)
        .focused(false)
        .visible_on_all_workspaces(true)
        .inner_size(settings.memo_width, settings.memo_height)
        .min_inner_size(MIN_MEMO_SIZE.0, MIN_MEMO_SIZE.1)
        .max_inner_size(MAX_MEMO_SIZE.0, MAX_MEMO_SIZE.1)
        .build()
        .map_err(|error| error.to_string())?;
    let ns_window = bubble_ns_window(&window).ok_or("memo window is missing")?;
    ns_window.setOpaque(false);
    ns_window.setBackgroundColor(Some(&NSColor::clearColor()));
    ns_window.setHasShadow(true);
    ns_window.setHidesOnDeactivate(false);
    ns_window.setCollectionBehavior(
        NSWindowCollectionBehavior::CanJoinAllSpaces | NSWindowCollectionBehavior::FullScreenAuxiliary | NSWindowCollectionBehavior::IgnoresCycle,
    );
    // The opaque webview body gets rounded corners from its own layer (public
    // API). No private "drawsBackground" switch is used.
    let _ = window.with_webview(|webview| unsafe {
        let view: &NSView = &*(webview.inner() as *const NSView);
        round_layer(view);
    });
    if let Some(content) = ns_window.contentView() {
        round_layer(&content);
    }
    Ok(())
}

fn with_character<T>(body: impl FnOnce(&NSPanel, &CharacterView) -> T) -> Option<T> {
    CHARACTER.with(|cell| cell.borrow().as_ref().map(|(panel, view)| body(panel, view)))
}

pub fn character_frame(_app: &AppHandle) -> Rect {
    let mtm = mtm();
    with_character(|panel, _| to_top_left(panel.frame(), mtm)).unwrap_or(Rect { x: 0.0, y: 0.0, width: 80.0, height: 80.0 })
}

pub fn set_character_origin(_app: &AppHandle, x: f64, y: f64) {
    let mtm = mtm();
    with_character(|panel, _| {
        let size = panel.frame().size;
        let frame = to_appkit(Rect { x, y, width: size.width, height: size.height }, mtm);
        panel.setFrameOrigin(frame.origin);
    });
}

pub fn set_character_visible(_app: &AppHandle, visible: bool) {
    with_character(|panel, _| {
        if visible {
            panel.orderFrontRegardless();
        } else {
            panel.orderOut(None);
        }
    });
}

pub fn set_character(_app: &AppHandle, choice: CharacterChoice, custom: Option<&Path>, size: f64) {
    let bytes: Option<Vec<u8>> = match choice {
        CharacterChoice::Classic => None,
        CharacterChoice::MemoWriter => Some(include_bytes!("../../assets/default-character.gif").to_vec()),
        CharacterChoice::OrbitingPlanet => Some(include_bytes!("../../assets/orbiting-planet.gif").to_vec()),
        CharacterChoice::Custom => custom.and_then(|path| std::fs::read(path).ok()),
    };
    let animate = !reduce_motion();
    let frames = bytes.as_deref().map(|bytes| decode_frames(bytes, animate)).unwrap_or_default();
    with_character(|panel, view| {
        // Keep the top-left corner fixed while resizing.
        let old = panel.frame();
        let top = old.origin.y + old.size.height;
        panel.setFrame_display(NSRect::new(NSPoint::new(old.origin.x, top - size), NSSize::new(size, size)), true);
        view.setFrame(NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(size, size)));
        view.setWantsLayer(true);

        if let Some(old_layer) = view.ivars().image_layer.borrow_mut().take() {
            old_layer.removeAllAnimations();
            old_layer.removeFromSuperlayer();
        }
        view.ivars().draws_classic.set(frames.is_empty());
        if let (Some(root), false) = (view.layer(), frames.is_empty()) {
            let layer = CALayer::new();
            layer.setFrame(NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(size, size)));
            layer.setContentsGravity(unsafe { kCAGravityResizeAspect });
            if let Some(window) = view.window() {
                layer.setContentsScale(window.backingScaleFactor());
            }
            let first = frames[0].0.clone();
            unsafe { layer.setContents(Some(cg_as_object(&first))) };
            if frames.len() > 1 {
                animate_frames(&layer, &frames);
            }
            root.addSublayer(&layer);
            *view.ivars().image_layer.borrow_mut() = Some(layer);
        }
        view.setNeedsDisplay(true);
        panel.invalidateShadow();
    });
}

type Frame = (Retained<objc2_core_graphics::CGImage>, f64);

/// Frames stay decoded in memory while they play. A picked image this long or
/// this large shows its first frame only; a huge one falls back to Classic.
const MAX_ANIMATION_FRAMES: isize = 240;
const MAX_ANIMATION_PIXELS: isize = 24 * 1024 * 1024; // all frames, about 96 MB
const MAX_IMAGE_PIXELS: isize = 16 * 1024 * 1024; // one frame, about 64 MB

/// The frames of a GIF/PNG/JPEG/WebP with their durations (seconds); only the
/// first one when `animate` is off.
fn decode_frames(bytes: &[u8], animate: bool) -> Vec<Frame> {
    let Some(rep) = NSBitmapImageRep::imageRepWithData(&NSData::with_bytes(bytes)) else { return Vec::new() };
    let pixels = rep.pixelsWide().max(1).saturating_mul(rep.pixelsHigh().max(1));
    if pixels > MAX_IMAGE_PIXELS {
        return Vec::new();
    }
    let mut count = rep
        .valueForProperty(unsafe { NSImageFrameCount })
        .and_then(|value| value.downcast::<NSNumber>().ok())
        .map(|number| number.integerValue())
        .unwrap_or(1)
        .max(1);
    if !animate || count > MAX_ANIMATION_FRAMES || count.saturating_mul(pixels) > MAX_ANIMATION_PIXELS {
        count = 1;
    }
    let mut frames = Vec::new();
    for index in 0..count {
        if count > 1 {
            unsafe { rep.setProperty_withValue(NSImageCurrentFrame, Some(&NSNumber::new_isize(index))) };
        }
        let duration = rep
            .valueForProperty(unsafe { NSImageCurrentFrameDuration })
            .and_then(|value| value.downcast::<NSNumber>().ok())
            .map(|number| number.doubleValue())
            .filter(|seconds| seconds.is_finite() && *seconds >= 0.02)
            .unwrap_or(0.1);
        if let Some(image) = rep.CGImage() {
            frames.push((image, duration));
        }
    }
    frames
}

fn cg_as_object(image: &objc2_core_graphics::CGImage) -> &AnyObject {
    // SAFETY: CGImageRef is a CoreFoundation object and therefore also an
    // Objective-C object; CALayer.contents takes it as `id`.
    unsafe { &*(image as *const objc2_core_graphics::CGImage as *const AnyObject) }
}

/// A discrete keyframe animation of the layer contents, played by the render
/// server instead of redrawing on the app's main thread.
fn animate_frames(layer: &CALayer, frames: &[Frame]) {
    let total: f64 = frames.iter().map(|(_, duration)| duration).sum();
    let values = NSMutableArray::<AnyObject>::new();
    let times = NSMutableArray::<NSNumber>::new();
    let mut elapsed = 0.0;
    for (image, duration) in frames {
        values.addObject(cg_as_object(image));
        times.addObject(&NSNumber::new_f64(elapsed / total));
        elapsed += duration;
    }
    // Discrete mode needs one more key time than values, ending at 1.0.
    times.addObject(&NSNumber::new_f64(1.0));
    let animation = CAKeyframeAnimation::animationWithKeyPath(Some(&NSString::from_str("contents")));
    unsafe {
        animation.setValues(Some(&values));
    }
    animation.setKeyTimes(Some(&times));
    animation.setCalculationMode(unsafe { kCAAnimationDiscrete });
    animation.setDuration(total);
    animation.setRepeatCount(f32::INFINITY);
    animation.setRemovedOnCompletion(false);
    layer.addAnimation_forKey(&animation, Some(&NSString::from_str("frames")));
}

/// Brings MemoPet to the front for a dialog it is about to show (image picker,
/// message). Without this the dialog appears, but typing still goes to the app
/// that was in front. The memo window does this itself through `set_focus`.
pub fn activate_app(_app: &AppHandle) {
    let Some(mtm) = MainThreadMarker::new() else { return };
    #[allow(deprecated)]
    NSApplication::sharedApplication(mtm).activateIgnoringOtherApps(true);
}

pub fn image_is_decodable(bytes: &[u8]) -> bool {
    NSImage::initWithData(NSImage::alloc(), &NSData::with_bytes(bytes)).is_some_and(|image| {
        let size = image.size();
        size.width > 0.0 && size.height > 0.0
    })
}

// ---------- memo bubble ----------

fn round_layer(view: &NSView) {
    view.setWantsLayer(true);
    if let Some(layer) = view.layer() {
        layer.setCornerRadius(12.0);
        layer.setMasksToBounds(true);
    }
}

fn bubble_ns_window(window: &tauri::WebviewWindow) -> Option<&'static NSWindow> {
    // SAFETY: Tauri keeps the NSWindow alive for the life of the app; the memo
    // window is never destroyed (closing is prevented in app::on_window_event).
    window.ns_window().ok().map(|pointer| unsafe { &*(pointer as *const NSWindow) })
}

fn bubble_window(app: &AppHandle) -> Option<tauri::WebviewWindow> {
    app.get_webview_window(BUBBLE_LABEL)
}

pub fn bubble_visible(_app: &AppHandle) -> bool {
    BUBBLE_SHOWN.load(Ordering::SeqCst)
}

pub fn bubble_focus_expected(_app: &AppHandle) -> bool {
    IGNORE_BLUR_UNTIL.with(|cell| cell.get().is_some_and(|until| Instant::now() < until))
}

pub fn bubble_is_focused(app: &AppHandle) -> bool {
    bubble_window(app).and_then(|window| bubble_ns_window(&window).map(|ns| ns.isKeyWindow())).unwrap_or(false)
}

pub fn bubble_size(app: &AppHandle) -> Option<(f64, f64)> {
    let window = bubble_window(app)?;
    let size = bubble_ns_window(&window)?.frame().size;
    Some((size.width, size.height))
}

pub fn show_bubble(app: &AppHandle, frame: Rect) {
    let mtm = mtm();
    let Some(window) = bubble_window(app) else { return };
    let Some(ns_window) = bubble_ns_window(&window) else { return };
    let front = NSWorkspace::sharedWorkspace().frontmostApplication();
    let ours = NSRunningApplication::currentApplication();
    PREVIOUS_APP.with(|cell| {
        *cell.borrow_mut() = front.filter(|app| app.processIdentifier() != ours.processIdentifier());
    });
    IGNORE_BLUR_UNTIL.with(|cell| cell.set(Some(Instant::now() + Duration::from_millis(400))));
    ns_window.setFrame_display(to_appkit(frame, mtm), true);
    BUBBLE_SHOWN.store(true, Ordering::SeqCst);
    let _ = window.show();
    let _ = window.set_focus();
    ns_window.invalidateShadow();
}

pub fn move_bubble(app: &AppHandle, frame: Rect) {
    let mtm = mtm();
    if let Some(window) = bubble_window(app) {
        if let Some(ns_window) = bubble_ns_window(&window) {
            ns_window.setFrame_display(to_appkit(frame, mtm), true);
        }
    }
}

/// Clicking another app keeps that choice (`explicit == false`). Esc or a
/// click on the character hands focus back to the app that was in front.
pub fn hide_bubble(app: &AppHandle, explicit: bool) {
    BUBBLE_SHOWN.store(false, Ordering::SeqCst);
    if let Some(window) = bubble_window(app) {
        let _ = window.hide();
    }
    let previous = PREVIOUS_APP.with(|cell| cell.borrow_mut().take());
    if explicit {
        if let Some(previous) = previous.filter(|app| !app.isTerminated()) {
            #[allow(deprecated)]
            previous.activateWithOptions(NSApplicationActivationOptions::ActivateIgnoringOtherApps);
        }
    }
}

// ---------- theme ----------

pub fn system_theme(_app: &AppHandle) -> Theme {
    let mtm = mtm();
    let names = NSArray::from_slice(&[unsafe { NSAppearanceNameDarkAqua }, unsafe { NSAppearanceNameAqua }]);
    let dark = NSApplication::sharedApplication(mtm)
        .effectiveAppearance()
        .bestMatchFromAppearancesWithNames(&names)
        .is_some_and(|name| name.to_string() == unsafe { NSAppearanceNameDarkAqua }.to_string());
    if dark { Theme::Dark } else { Theme::Light }
}

/// The memo window's appearance also drives the page's
/// `prefers-color-scheme`; the native character follows its panel's.
pub fn set_theme(app: &AppHandle, theme: Theme) {
    let name = match theme {
        Theme::Light => unsafe { NSAppearanceNameAqua },
        Theme::Dark => unsafe { NSAppearanceNameDarkAqua },
    };
    let appearance = NSAppearance::appearanceNamed(name);
    with_character(|panel, view| {
        panel.setAppearance(appearance.as_deref());
        view.setNeedsDisplay(true);
    });
    if let Some(window) = bubble_window(app) {
        let _ = window.set_theme(Some(match theme {
            Theme::Light => tauri::Theme::Light,
            Theme::Dark => tauri::Theme::Dark,
        }));
    }
}

// ---------- shared entry points that only Windows needs ----------

pub fn on_window_event(_window: &tauri::Window, _event: &tauri::WindowEvent) {}

pub fn character_look(_app: &AppHandle) -> serde_json::Value {
    serde_json::json!({ "kind": "classic", "source": null, "animate": true })
}

pub fn show_character_menu(_app: &AppHandle) {}

#[cfg(test)]
mod tests {
    use super::decode_frames;

    const WRITER: &[u8] = include_bytes!("../../assets/default-character.gif");

    #[test]
    fn decodes_every_frame_only_when_animating() {
        assert_eq!(decode_frames(WRITER, true).len(), 30);
        assert_eq!(decode_frames(WRITER, false).len(), 1);
    }

    #[test]
    fn long_or_huge_images_are_limited() {
        // 241 frames is over the frame limit: first frame only.
        assert_eq!(decode_frames(include_bytes!("../../test-fixtures/241-frames.gif"), true).len(), 1);
        // 4100 × 4100 is just over the pixel limit for one frame: nothing (Classic).
        assert!(decode_frames(include_bytes!("../../test-fixtures/4100x4100.png"), true).is_empty());
        assert!(decode_frames(b"not an image", true).is_empty());
    }
}
