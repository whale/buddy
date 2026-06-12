// Buddy — Tauri v2 Mac shell.
//
// ⚠️ UNVERIFIED SCAFFOLD. This Rust has never been compiled or run by the agent
// that wrote it (no Rust toolchain available in that environment). Expect to fix
// small compile errors on the first `pnpm tauri dev`. See README-MAC.md.
//
// What this shell does:
//   • Loads the existing single-file web app (../index.html) into a borderless,
//     transparent, always-on-top webview pinned to the RIGHT EDGE of the active
//     monitor at full height.
//   • Adds a menu-bar (tray) icon. Left-click toggles the window show/hide.
//     The tray menu has Show/Hide and Quit.
//   • Registers the backtick key ( ` ) as a GLOBAL shortcut that shows + focuses
//     the window (stand-in summon hotkey; mirrors the in-app `\`` drawer toggle).
//
// KNOWN-FRAGILE / MORNING WORK (documented, not solved here — see PLAN §11):
//   • Non-activating NSPanel behaviour + exact NSWindowLevel are NOT set here.
//     Tauri v2 doesn't expose them; doing it right needs Rust→AppKit via objc2,
//     testable only on the machine.
//   • "Reserved space" (other windows can't sit behind Buddy) is NOT implemented.
//   • A plain global `\`` will be swallowed app-wide (you won't be able to type a
//     backtick anywhere while Buddy runs). That's intentional for the prototype;
//     you'll likely move the summon to a chord (e.g. Cmd+\`) — noted in README.

use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, PhysicalPosition, PhysicalSize, WebviewWindow,
};

/// Width (in logical-ish physical px) of the Buddy strip on screen.
/// Tweak to taste; the web layout is comfortable around 320–360.
const STRIP_WIDTH: u32 = 420;

/// Position `win` flush against the right edge of whichever monitor it currently
/// sits on (falls back to the primary monitor), spanning the full usable height.
///
/// NOTE: uses the full monitor size. It does NOT subtract the menu-bar / notch,
/// so on a notched display the top ~25–32pt may sit under the menu bar until the
/// NSPanel/safe-area work is done. Adjust `y` + `height` once measured on-device.
fn position_right_edge(win: &WebviewWindow) {
    // Prefer the monitor the window is on; fall back to primary; then bail quietly.
    let monitor = win
        .current_monitor()
        .ok()
        .flatten()
        .or_else(|| win.primary_monitor().ok().flatten());

    let Some(monitor) = monitor else {
        eprintln!("[buddy] no monitor found; skipping reposition");
        return;
    };

    let m_pos = monitor.position(); // top-left of this monitor in the virtual desktop
    let m_size = monitor.size(); // physical pixels
    let scale = monitor.scale_factor();

    // Convert our logical strip width to physical pixels for this monitor.
    let width_px = (STRIP_WIDTH as f64 * scale).round() as u32;
    // Sit below the menu bar (~25pt) so the window doesn't run off the top.
    let top_px = (25.0 * scale).round() as i32;
    let height_px = (m_size.height as i32 - top_px).max(200) as u32;

    let x = m_pos.x + (m_size.width as i32 - width_px as i32);
    let y = m_pos.y + top_px;

    if let Err(e) = win.set_size(PhysicalSize::new(width_px, height_px)) {
        eprintln!("[buddy] set_size failed: {e}");
    }
    if let Err(e) = win.set_position(PhysicalPosition::new(x, y)) {
        eprintln!("[buddy] set_position failed: {e}");
    }
}

/// Show + position + focus the main window.
fn show_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        position_right_edge(&win);
        let _ = win.show();
        let _ = win.unminimize();
        let _ = win.set_focus();
    }
}

/// Hide the main window.
fn hide_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.hide();
    }
}

/// Toggle show/hide based on current visibility.
fn toggle_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        match win.is_visible() {
            Ok(true) => {
                let _ = win.hide();
            }
            _ => show_window(app),
        }
    }
}

/// Diagnostic: the webview console isn't forwarded to the terminal, so JS calls
/// this to log into the same file we can read. (Temporary.)
#[tauri::command]
fn trace(msg: String) {
    eprintln!("[buddy-js] {msg}");
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default();

    // Global shortcut plugin — desktop only. Backtick summons Buddy.
    #[cfg(desktop)]
    {
        use tauri_plugin_global_shortcut::{Builder as GsBuilder, ShortcutState};

        builder = builder.plugin(
            GsBuilder::new()
                .with_handler(|app, _shortcut, event| {
                    // Fire once, on key-down only (ignore the release event).
                    if event.state == ShortcutState::Pressed {
                        show_window(app);
                    }
                })
                .build(),
        );
    }

    builder
        .invoke_handler(tauri::generate_handler![trace])
        .setup(|app| {
            let handle = app.handle();

            // --- Menu-bar (tray) icon + menu ---
            let toggle_item = MenuItemBuilder::with_id("toggle", "Show / Hide Buddy").build(app)?;
            let quit_item = MenuItemBuilder::with_id("quit", "Quit Buddy").build(app)?;
            let menu = MenuBuilder::new(app)
                .items(&[&toggle_item])
                .separator()
                .items(&[&quit_item])
                .build()?;

            let _tray = TrayIconBuilder::with_id("buddy-tray")
                .icon(app.default_window_icon().cloned().expect("no window icon"))
                // `icon_as_template(true)` makes macOS tint a black-on-transparent
                // icon for light/dark menu bars. Our placeholder tray PNG is built
                // that way. If you swap in a colored icon, set this to false.
                .icon_as_template(true)
                .tooltip("Buddy")
                .menu(&menu)
                // Show the menu only on right-click; left-click toggles the window.
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "toggle" => toggle_window(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_window(tray.app_handle());
                    }
                })
                .build(app)?;

            // --- Register the backtick global shortcut ---
            #[cfg(desktop)]
            {
                use tauri_plugin_global_shortcut::GlobalShortcutExt;
                // "Backquote" is the physical ` / ~ key. If this errors on your
                // layout, try the literal "`" or a chord like "CmdOrCtrl+`".
                if let Err(e) = handle.global_shortcut().register("Backquote") {
                    eprintln!("[buddy] could not register `\\`` global shortcut: {e}");
                    eprintln!("[buddy] (try a chord such as CmdOrCtrl+` instead — see README-MAC.md)");
                }
            }

            // Reveal on launch WITHOUT positioning — the web layer (nativeFit) owns
            // sizing/position so the full-screen morning isn't snapped back to the strip.
            if let Some(win) = handle.get_webview_window("main") {
                let _ = win.show();
                let _ = win.set_focus();
            }

            // No Dock icon: behave like a menu-bar utility (macOS "Accessory").
            #[cfg(target_os = "macos")]
            {
                let _ = app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            match event {
                tauri::WindowEvent::Resized(sz) => eprintln!("[buddy-win] Resized {}x{}", sz.width, sz.height),
                tauri::WindowEvent::Moved(p) => eprintln!("[buddy-win] Moved {},{}", p.x, p.y),
                tauri::WindowEvent::Focused(f) => eprintln!("[buddy-win] Focused {}", f),
                // Closing (e.g. Cmd+W) just hides — Buddy lives in the menu bar.
                tauri::WindowEvent::CloseRequested { api, .. } => { api.prevent_close(); let _ = window.hide(); }
                _ => {}
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running Buddy");
}
