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
    AppHandle, Emitter, Manager,
};

/// Tell the webview to toggle the drawer (from the tray icon or the global
/// shortcut). The webview owns its own geometry via `nativeFit`, so the native
/// side just emits an intent and lets JS open or tuck — no window juggling here.
fn toggle_drawer(app: &AppHandle) {
    let _ = app.emit("buddy://toggle", ());
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
                        toggle_drawer(app);
                    }
                })
                .build(),
        );
    }

    builder
        .invoke_handler(tauri::generate_handler![trace])
        .setup(|app| {
            // Own the handle (clone) so it doesn't hold an immutable borrow of `app`
            // across the later `set_activation_policy` call (which needs `&mut app`).
            let handle = app.handle().clone();

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
                    "toggle" => toggle_drawer(app),
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
                        toggle_drawer(tray.app_handle());
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

            // --- Global cursor monitor: owns BOTH reveal and hide --------------
            // A webview can only sense the mouse inside its own window, and its
            // mouse-leave fires unreliably the instant the cursor crosses the
            // (transparent, non-focused) window border — that was the finicky
            // "won't tuck back" bug. So one poll of the REAL OS cursor drives
            // everything. We classify the cursor into three zones and act only on
            // the transition INTO a zone (not 60×/sec):
            //   zone 2 = touching the right screen edge → reveal
            //   zone 1 = over the open drawer            → stay
            //   zone 0 = left of the drawer              → hide
            // Same poll, both directions → rock-solid, no web mouse-leave needed.
            #[cfg(target_os = "macos")]
            {
                let h = handle.clone();
                std::thread::spawn(move || {
                    use mouse_position::mouse_position::Mouse;
                    const DRAWER_W: f64 = 420.0; // matches DRAWERW in index.html
                    const TICK_MS: u64 = 16;
                    // Dwell times: the cursor must REST at the edge before revealing
                    // (so a quick brush-past doesn't pop it), and rest off the drawer
                    // a moment before hiding (so a small drift doesn't snap it shut).
                    const REVEAL_DWELL: u32 = 500 / TICK_MS as u32; // ~31 ticks ≈ 500ms
                    const HIDE_GRACE: u32 = 160 / TICK_MS as u32; //  ~10 ticks ≈ 160ms
                    let mut edge_ticks = 0u32; // consecutive ticks at the edge
                    let mut away_ticks = 0u32; // consecutive ticks off the drawer
                    let mut edge_fired = false; // revealed during this edge visit
                    let mut away_fired = false; // hidden during this away visit
                    loop {
                        std::thread::sleep(std::time::Duration::from_millis(TICK_MS));
                        // Right edge of the primary monitor, in logical points
                        // (CGEvent reports the cursor in points too, so units match).
                        let Some(mon) = h
                            .get_webview_window("main")
                            .and_then(|w| w.primary_monitor().ok().flatten())
                        else {
                            continue;
                        };
                        let scale = mon.scale_factor();
                        let right = (mon.position().x as f64 + mon.size().width as f64) / scale;

                        if let Mouse::Position { x, .. } = Mouse::get_mouse_position() {
                            let x = x as f64;
                            if x >= right - 2.0 {
                                // At the edge → count toward reveal.
                                away_ticks = 0;
                                away_fired = false;
                                edge_ticks += 1;
                                if edge_ticks >= REVEAL_DWELL && !edge_fired {
                                    edge_fired = true;
                                    let _ = h.emit("buddy://reveal", ());
                                }
                            } else if x < right - DRAWER_W {
                                // Off the drawer entirely → count toward hide.
                                edge_ticks = 0;
                                edge_fired = false;
                                away_ticks += 1;
                                if away_ticks >= HIDE_GRACE && !away_fired {
                                    away_fired = true;
                                    let _ = h.emit("buddy://hide", ());
                                }
                            } else {
                                // Over the open drawer → neutral; reset both dwells.
                                edge_ticks = 0;
                                away_ticks = 0;
                                edge_fired = false;
                                away_fired = false;
                            }
                        }
                    }
                });
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
