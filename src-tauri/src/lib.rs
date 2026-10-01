pub mod core;

mod app;
mod characters;
mod i18n;
mod platform;
mod settings;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default().plugin(tauri_plugin_dialog::init());
    // macOS already keeps one instance per app bundle (and the plugin's
    // socket would sit outside the App Sandbox), so only Windows needs it.
    #[cfg(not(target_os = "macos"))]
    let builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || app::open_bubble(&handle));
    }));
    builder
        .setup(app::setup)
        .on_window_event(app::on_window_event)
        .invoke_handler(tauri::generate_handler![
            app::load_notebook,
            app::ui_info,
            app::dismiss_tip,
            app::save_note,
            app::select_note,
            app::add_note,
            app::delete_note,
            app::rename_note,
            app::move_note,
            app::close_bubble,
            app::quit_ack,
            app::quit_app,
            app::quit_cancelled,
            app::open_memo,
            app::character_clicked,
            app::character_menu,
            app::character_look,
        ])
        .build(tauri::generate_context!())
        .expect("error while building MemoBuddy")
        .run(|app, event| {
            // A quit that did not come from our own `app.exit` (Tauri sends
            // this when every window is gone): let the memo page save first.
            // The page then calls `quit_app`, which exits with an explicit code.
            // ⌘Q goes through the app menu (`install_app_menu`) instead. Logout
            // and shutdown do not come here: tao only handles
            // applicationWillTerminate (see docs/RELEASE.md, known limits).
            if let tauri::RunEvent::ExitRequested { code: None, api, .. } = event {
                if app::begin_quit(app) {
                    api.prevent_exit();
                }
            }
        });
}
