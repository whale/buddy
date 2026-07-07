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
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager,
};
use tauri_plugin_updater::UpdaterExt;

/// Summon Buddy from the tray icon or the global shortcut. ALWAYS raise the OS
/// window first, THEN emit the drawer intent. The raise is the important half:
/// without it, when the window is open-but-occluded — most painfully full-screen
/// morning, where the JS intent below is a deliberate no-op (`if(morningUp())
/// return`) — the user is stranded behind another app with no way back in. The
/// webview still owns its geometry via `nativeFit`; we only guarantee it's
/// visible and frontmost so the keypress can never leave Buddy hidden.
fn toggle_drawer(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.set_focus();
    }
    let _ = app.emit("buddy://toggle", ());
}

/// Summon the morning planner on demand (the hidden ⌘⌥⌃M show-off shortcut).
/// Like `toggle_drawer`, we RAISE the OS window FIRST: a JS-only keydown can't
/// bring its own occluded window frontmost, so morning flashed then hid behind
/// the active app. Raise + focus here, then emit the intent for the web layer.
fn summon_morning(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.set_focus();
    }
    let _ = app.emit("buddy://morning", ());
}

/// macOS: allow this (alwaysOnTop) window to be shown in the SAME Space as an app
/// that's in native full-screen mode. Without `FullScreenAuxiliary`, a floating
/// window lives only on the desktop Space, so when the user is in a full-screen
/// browser, Buddy's morning flashes on the desktop then "hides behind" it. Adding
/// `CanJoinAllSpaces` keeps it present as the user switches Spaces too.
#[cfg(target_os = "macos")]
fn allow_over_fullscreen(win: &tauri::WebviewWindow) {
    use objc2_app_kit::{NSWindow, NSWindowCollectionBehavior};
    let Ok(ptr) = win.ns_window() else { return };
    if ptr.is_null() {
        return;
    }
    let ns = ptr as *const NSWindow;
    unsafe {
        let Some(ns) = ns.as_ref() else { return };
        let behavior = ns.collectionBehavior()
            | NSWindowCollectionBehavior::CanJoinAllSpaces
            | NSWindowCollectionBehavior::FullScreenAuxiliary;
        ns.setCollectionBehavior(behavior);
        eprintln!("[buddy] over-fullscreen behaviour set: {:?}", ns.collectionBehavior());
    }
}

/// Diagnostic: the webview console isn't forwarded to the terminal, so JS calls
/// this to log into the same file we can read. (Temporary.)
#[tauri::command]
fn trace(msg: String) {
    eprintln!("[buddy-js] {msg}");
}

/// Quit the app (from the Settings "Quit Buddy" row).
#[tauri::command]
fn quit(app: AppHandle) {
    app.exit(0);
}

/// Morning-planner window mode. ON: drop always-on-top and become a normal Dock /
/// ⌘-Tab app (Regular) so the user can tab away to a meeting and back, and raise to
/// front — but NOT locked on top, so other apps can come forward (no takeover). OFF:
/// back to the quiet edge-drawer (always-on-top, Accessory / no Dock icon).
#[tauri::command]
fn set_morning_mode(app: AppHandle, on: bool) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.set_always_on_top(!on);
        if on {
            let _ = win.show();
            let _ = win.set_focus();
        }
    }
    #[cfg(target_os = "macos")]
    {
        let policy = if on {
            tauri::ActivationPolicy::Regular
        } else {
            tauri::ActivationPolicy::Accessory
        };
        let _ = app.set_activation_policy(policy);
    }
}

/// The running version, baked in from Cargo.toml at compile time.
#[tauri::command]
fn app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// True for debug (dev) builds, false for release. Drives the "Dev Buddy" header.
#[tauri::command]
fn is_dev() -> bool {
    cfg!(debug_assertions)
}

/// Percent-encode for a mailto: URL (unreserved chars pass through).
fn percent_encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{:02X}", b),
        })
        .collect()
}

/// Report a bug: the webview hands us a PNG screenshot of ONLY Buddy's UI plus a
/// logs string. Preferred path — write a zip and open an Apple Mail draft with it
/// ALREADY ATTACHED (no paste). If Mail scripting isn't available (other mail app
/// or permission denied), fall back to: screenshot on the clipboard + logs in the
/// body of a default-client draft (paste with ⌘V).
#[tauri::command]
fn report_bug(screenshot: String, logs: String) -> Result<(), String> {
    use base64::{engine::general_purpose, Engine as _};
    use std::io::Write;

    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let dir = std::env::temp_dir().join(format!("buddy-bug-{ts}"));
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;

    let png = dir.join("buddy-screenshot.png");
    let txt = dir.join("buddy-logs.txt");
    let b64 = screenshot.split(',').last().unwrap_or("");
    if let Ok(bytes) = general_purpose::STANDARD.decode(b64) {
        if let Ok(mut f) = std::fs::File::create(&png) { let _ = f.write_all(&bytes); }
    }
    let _ = std::fs::write(&txt, logs.as_bytes());

    // Preferred: Apple Mail draft with the zip attached, nothing to paste.
    let zip = dir.join("buddy-bug-report.zip");
    let _ = std::process::Command::new("zip").arg("-j").arg(&zip).arg(&png).arg(&txt).output();
    let mail_script = format!(
        "tell application \"Mail\"\nset m to make new outgoing message with properties {{subject:\"Buddy bug report\", visible:true}}\ntell m\nmake new to recipient at end of to recipients with properties {{address:\"hi+buddy@whale.fyi\"}}\nset content to \"Describe what happened here — the screenshot and logs are attached. Thank you!\"\ndelay 0.5\nmake new attachment with properties {{file name:POSIX file \"{}\"}} at after the last paragraph\nend tell\nactivate\nend tell",
        zip.to_string_lossy()
    );
    let mail_ok = std::process::Command::new("osascript")
        .arg("-e").arg(&mail_script)
        .status().map(|s| s.success()).unwrap_or(false);
    if mail_ok { return Ok(()); }

    // Fallback (other mail apps): screenshot on the clipboard, logs in the body.
    let set_clip = format!(
        "set the clipboard to (read (POSIX file \"{}\") as \u{00AB}class PNGf\u{00BB})",
        png.to_string_lossy()
    );
    let _ = std::process::Command::new("osascript").arg("-e").arg(&set_clip).status();
    let diag: String = logs.chars().take(2500).collect();
    let body = format!(
        "Describe what happened:\n\n\n\n— Paste your screenshot here (\u{2318}V) —\n\n\n--- diagnostics ---\n{diag}"
    );
    let mailto = format!(
        "mailto:hi+buddy@whale.fyi?subject={}&body={}",
        percent_encode("Buddy bug report"),
        percent_encode(&body)
    );
    let _ = std::process::Command::new("open").arg(mailto).spawn();
    Ok(())
}

// ============ "Reserve space when pinned" — Accessibility window nudging ============
// When ON, a background loop watches other apps' on-screen windows and pushes any
// that intrude into Buddy's right-edge column back out (shrink if wide, else slide
// left). It's an approximation (can't touch fullscreen/non-resizable windows) and
// needs the user's Accessibility permission. Off by default.
#[cfg(target_os = "macos")]
mod reserve {
    use core_foundation::base::{CFRelease, CFTypeRef, TCFType};
    use core_foundation::boolean::CFBoolean;
    use core_foundation::dictionary::{CFDictionary, CFDictionaryRef};
    use core_foundation::string::{CFString, CFStringRef};
    use core_foundation::array::CFArrayRef;
    use core_graphics::geometry::{CGPoint, CGRect, CGSize};
    use std::os::raw::c_void;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Duration;

    static ACTIVE: AtomicBool = AtomicBool::new(false);
    static STARTED: AtomicBool = AtomicBool::new(false);
    const STRIP: f64 = 416.0; // visible drawer width (incl. an ~8px gap to the card — matches Buddy's inter-card gap)
    const MIN_W: f64 = 240.0; // never shrink a window narrower than this
    const AX_POINT: u32 = 1; // kAXValueCGPointType
    const AX_SIZE: u32 = 2; // kAXValueCGSizeType
    const CF_SINT32: i32 = 3; // kCFNumberSInt32Type

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXUIElementCreateApplication(pid: i32) -> CFTypeRef;
        fn AXUIElementCopyAttributeValue(el: CFTypeRef, attr: CFStringRef, out: *mut CFTypeRef) -> i32;
        fn AXUIElementSetAttributeValue(el: CFTypeRef, attr: CFStringRef, val: CFTypeRef) -> i32;
        fn AXValueCreate(ty: u32, ptr: *const c_void) -> CFTypeRef;
        fn AXValueGetValue(val: CFTypeRef, ty: u32, ptr: *mut c_void) -> bool;
        fn AXIsProcessTrusted() -> bool;
        fn AXIsProcessTrustedWithOptions(options: CFDictionaryRef) -> bool;
    }
    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGMainDisplayID() -> u32;
        fn CGDisplayBounds(display: u32) -> CGRect;
        fn CGWindowListCopyWindowInfo(option: u32, rel: u32) -> CFArrayRef;
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFArrayGetCount(a: CFArrayRef) -> isize;
        fn CFArrayGetValueAtIndex(a: CFArrayRef, idx: isize) -> *const c_void;
        fn CFDictionaryGetValue(d: *const c_void, key: *const c_void) -> *const c_void;
        fn CFNumberGetValue(n: *const c_void, ty: i32, value: *mut c_void) -> bool;
        fn CFBooleanGetValue(b: CFTypeRef) -> bool;
    }

    fn cfs(v: &str) -> CFString { CFString::new(v) }

    fn prompt_trust() -> bool {
        unsafe {
            let dict = CFDictionary::from_CFType_pairs(&[(
                cfs("AXTrustedCheckOptionPrompt").as_CFType(),
                CFBoolean::true_value().as_CFType(),
            )]);
            AXIsProcessTrustedWithOptions(dict.as_concrete_TypeRef())
        }
    }

    unsafe fn copy_attr(el: CFTypeRef, attr: &str) -> Option<CFTypeRef> {
        let mut out: CFTypeRef = std::ptr::null();
        if AXUIElementCopyAttributeValue(el, cfs(attr).as_concrete_TypeRef(), &mut out) == 0 && !out.is_null() {
            Some(out)
        } else {
            None
        }
    }
    unsafe fn ax_point(win: CFTypeRef, attr: &str) -> Option<CGPoint> {
        let v = copy_attr(win, attr)?;
        let mut p = CGPoint { x: 0.0, y: 0.0 };
        let ok = AXValueGetValue(v, AX_POINT, &mut p as *mut _ as *mut c_void);
        CFRelease(v);
        if ok { Some(p) } else { None }
    }
    unsafe fn ax_size(win: CFTypeRef, attr: &str) -> Option<CGSize> {
        let v = copy_attr(win, attr)?;
        let mut sz = CGSize { width: 0.0, height: 0.0 };
        let ok = AXValueGetValue(v, AX_SIZE, &mut sz as *mut _ as *mut c_void);
        CFRelease(v);
        if ok { Some(sz) } else { None }
    }
    unsafe fn ax_set(win: CFTypeRef, attr: &str, ty: u32, ptr: *const c_void) {
        let v = AXValueCreate(ty, ptr);
        if !v.is_null() {
            AXUIElementSetAttributeValue(win, cfs(attr).as_concrete_TypeRef(), v);
            CFRelease(v);
        }
    }
    unsafe fn ax_string(win: CFTypeRef, attr: &str) -> Option<String> {
        let v = copy_attr(win, attr)?;
        Some(CFString::wrap_under_create_rule(v as CFStringRef).to_string())
    }
    unsafe fn ax_is_true(win: CFTypeRef, attr: &str) -> bool {
        if let Some(v) = copy_attr(win, attr) { let b = CFBooleanGetValue(v); CFRelease(v); b } else { false }
    }

    // Pids of apps that own a NORMAL window (window layer 0). Layer 0 = ordinary
    // app windows; the volume/brightness HUD, menu bar, Dock, notifications,
    // Control Center, Spotlight, etc. all live on higher layers, so they're
    // skipped here and never touched.
    unsafe fn owner_pids(own: i32) -> Vec<i32> {
        let arr = CGWindowListCopyWindowInfo(1 /* onScreenOnly */, 0);
        if arr.is_null() { return vec![]; }
        let pid_key = cfs("kCGWindowOwnerPID");
        let pid_ref = pid_key.as_concrete_TypeRef() as *const c_void;
        let layer_key = cfs("kCGWindowLayer");
        let layer_ref = layer_key.as_concrete_TypeRef() as *const c_void;
        let mut pids: Vec<i32> = vec![];
        let n = CFArrayGetCount(arr);
        for i in 0..n {
            let dict = CFArrayGetValueAtIndex(arr, i);
            if dict.is_null() { continue; }
            // Only normal-layer windows.
            let lval = CFDictionaryGetValue(dict, layer_ref);
            let mut layer: i32 = -1;
            if !lval.is_null() { CFNumberGetValue(lval, CF_SINT32, &mut layer as *mut _ as *mut c_void); }
            if layer != 0 { continue; }
            let val = CFDictionaryGetValue(dict, pid_ref);
            if val.is_null() { continue; }
            let mut pid: i32 = 0;
            if CFNumberGetValue(val, CF_SINT32, &mut pid as *mut _ as *mut c_void)
                && pid > 0 && pid != own && !pids.contains(&pid)
            {
                pids.push(pid);
            }
        }
        CFRelease(arr as CFTypeRef);
        pids
    }

    unsafe fn nudge(strip_left: f64) {
        let own = std::process::id() as i32;
        for pid in owner_pids(own) {
            let app = AXUIElementCreateApplication(pid);
            if app.is_null() { continue; }
            if let Some(wins) = copy_attr(app, "AXWindows") {
                let warr = wins as CFArrayRef;
                let wc = CFArrayGetCount(warr);
                for j in 0..wc {
                    let win = CFArrayGetValueAtIndex(warr, j) as CFTypeRef;
                    if win.is_null() { continue; }
                    // Only real document windows — skip dialogs, sheets, popovers,
                    // panels (non-AXStandardWindow) and minimized windows.
                    if ax_string(win, "AXSubrole").as_deref() != Some("AXStandardWindow") { continue; }
                    if ax_is_true(win, "AXMinimized") { continue; }
                    if let (Some(pos), Some(sz)) = (ax_point(win, "AXPosition"), ax_size(win, "AXSize")) {
                        if pos.x + sz.width > strip_left + 1.0 {
                            if pos.x < strip_left - MIN_W {
                                let ns = CGSize { width: strip_left - pos.x, height: sz.height };
                                ax_set(win, "AXSize", AX_SIZE, &ns as *const _ as *const c_void);
                            } else {
                                let np = CGPoint { x: (strip_left - sz.width).max(0.0), y: pos.y };
                                ax_set(win, "AXPosition", AX_POINT, &np as *const _ as *const c_void);
                            }
                        }
                    }
                }
                CFRelease(wins);
            }
            CFRelease(app);
        }
    }

    pub fn set(on: bool) {
        ACTIVE.store(on, Ordering::SeqCst);
        if on {
            prompt_trust(); // shows the one-time Accessibility prompt if not yet granted
            if !STARTED.swap(true, Ordering::SeqCst) {
                std::thread::spawn(|| loop {
                    std::thread::sleep(Duration::from_millis(700));
                    if !ACTIVE.load(Ordering::SeqCst) { continue; }
                    unsafe {
                        if !AXIsProcessTrusted() { continue; }
                        let b = CGDisplayBounds(CGMainDisplayID());
                        nudge(b.origin.x + b.size.width - STRIP);
                    }
                });
            }
        }
    }
}

/// Toggle "reserve space when pinned" (JS calls this when pin/setting changes).
#[tauri::command]
fn set_reserve(on: bool) {
    #[cfg(target_os = "macos")]
    reserve::set(on);
    #[cfg(not(target_os = "macos"))]
    let _ = on;
}

// ============ Durable state file — the origin-independent source of truth ============
// localStorage is bound to the webview ORIGIN, so a dev-port change / dev→prod / a
// Tauri config change opens a different (often empty) store and strands the old data.
// We mirror every save to a plain JSON file in the app-data dir, which is
// origin-independent and survives a localStorage clear. Written atomically (temp file
// + rename) so a crash mid-write can never truncate the good copy.
fn state_file(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path().app_data_dir().ok().map(|d| d.join("buddy-state.json"))
}

// Last state that looked recoverable. This is deliberately separate from the
// primary file: if a bad launch writes an empty same-day state, the recovery file
// keeps the last real task list instead of being overwritten by that empty save.
fn recovery_state_file(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path().app_data_dir().ok().map(|d| d.join("buddy-state.recovery.json"))
}

fn state_has_array_items(v: &serde_json::Value, path: &[&str]) -> bool {
    let mut cur = v;
    for key in path {
        cur = match cur.get(*key) {
            Some(next) => next,
            None => return false,
        };
    }
    cur.as_array().map(|a| !a.is_empty()).unwrap_or(false)
}

fn state_has_object_items(v: &serde_json::Value, key: &str) -> bool {
    v.get(key)
        .and_then(|x| x.as_object())
        .map(|o| !o.is_empty())
        .unwrap_or(false)
}

fn is_recoverable_state(blob: &str) -> bool {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(blob) else {
        return false;
    };
    state_has_array_items(&v, &["today", "items"])
        || state_has_array_items(&v, &["deferred"])
        || state_has_object_items(&v, "tombstones")
        || !v.get("erasedAt").unwrap_or(&serde_json::Value::Null).is_null()
}

fn today_items_len(v: &serde_json::Value) -> usize {
    v.pointer("/today/items")
        .and_then(|x| x.as_array())
        .map(|a| a.len())
        .unwrap_or(0)
}

// DURABILITY RATCHET: the recovery file exists to survive an accidental empty save, so
// it must NEVER be overwritten by a blob that has FEWER today-items than what it already
// holds for the same (or older) day — unless a real "erase all" (a newer erasedAt)
// explains the drop. Without this, a normal day's leftover tombstones made an empty-today
// save look "recoverable" and it clobbered the last real task list (the original data-loss
// bug). Returns true when we should KEEP the existing recovery file and skip the write.
fn recovery_should_keep_existing(new_blob: &str, existing: &str) -> bool {
    let (Ok(n), Ok(e)) = (
        serde_json::from_str::<serde_json::Value>(new_blob),
        serde_json::from_str::<serde_json::Value>(existing),
    ) else {
        return false; // can't compare → don't block the write
    };
    let n_erased = n.get("erasedAt").and_then(|x| x.as_i64());
    let e_erased = e.get("erasedAt").and_then(|x| x.as_i64()).unwrap_or(0);
    if n_erased.unwrap_or(0) > e_erased {
        return false; // a real erase-all explains the empty → allow overwrite
    }
    let n_date = n.pointer("/today/date").and_then(|x| x.as_str());
    let e_date = e.pointer("/today/date").and_then(|x| x.as_str());
    if let (Some(nd), Some(ed)) = (n_date, e_date) {
        if nd > ed {
            return false; // genuinely a newer day → ok for it to start empty
        }
    }
    today_items_len(&n) < today_items_len(&e) // same/older day with fewer items → keep existing
}

#[tauri::command]
fn load_state(app: AppHandle) -> Option<String> {
    let p = state_file(&app)?;
    std::fs::read_to_string(p).ok()
}

#[tauri::command]
fn load_recovery_state(app: AppHandle) -> Option<String> {
    let p = recovery_state_file(&app)?;
    std::fs::read_to_string(p).ok()
}

#[tauri::command]
fn save_state(app: AppHandle, blob: String) -> Result<(), String> {
    let p = state_file(&app).ok_or("no app data dir")?;
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let tmp = p.with_extension("json.tmp");
    std::fs::write(&tmp, blob.as_bytes()).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &p).map_err(|e| e.to_string())?;

    if is_recoverable_state(&blob) {
        if let Some(rp) = recovery_state_file(&app) {
            // Ratchet: don't let an emptier same/older-day blob overwrite a fuller recovery.
            let keep_existing = std::fs::read_to_string(&rp)
                .ok()
                .map(|existing| recovery_should_keep_existing(&blob, &existing))
                .unwrap_or(false);
            if !keep_existing {
                let rtmp = rp.with_extension("json.tmp");
                if std::fs::write(&rtmp, blob.as_bytes()).is_ok() {
                    let _ = std::fs::rename(&rtmp, &rp);
                }
            }
        }
    }

    Ok(())
}

/// Auto-updater: ask GitHub Releases whether a newer signed build exists.
/// Returns Some(version) if an update is available, None if we're current.
#[tauri::command]
async fn check_for_update(app: AppHandle) -> Result<Option<String>, String> {
    let updater = app.updater().map_err(|e| e.to_string())?;
    match updater.check().await {
        Ok(Some(update)) => Ok(Some(update.version)),
        Ok(None) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

/// Auto-updater: download + install the available update, then relaunch into it.
#[tauri::command]
async fn install_update(app: AppHandle) -> Result<(), String> {
    let updater = app.updater().map_err(|e| e.to_string())?;
    let update = updater
        .check()
        .await
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "No update available".to_string())?;
    update
        .download_and_install(|_chunk, _total| {}, || {})
        .await
        .map_err(|e| e.to_string())?;
    app.restart();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default();

    // Single-instance guard MUST be the first plugin registered (Tauri requirement).
    // If Buddy is already running, a second launch just focuses the existing window —
    // two webviews must never fight over the same state file.
    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.show();
                let _ = win.set_focus();
            }
        }));
    }

    // Global shortcut plugin — desktop only. Backtick summons Buddy.
    #[cfg(desktop)]
    {
        use tauri_plugin_global_shortcut::{Builder as GsBuilder, ShortcutState};

        builder = builder.plugin(
            GsBuilder::new()
                .with_handler(|app, shortcut, event| {
                    // Fire once, on key-down only (ignore the release event).
                    if event.state == ShortcutState::Pressed {
                        use tauri_plugin_global_shortcut::{Code, Modifiers};
                        // ⌘⌥⌃M summons the morning planner; ` toggles the drawer.
                        if shortcut.matches(
                            Modifiers::SUPER | Modifiers::ALT | Modifiers::CONTROL,
                            Code::KeyM,
                        ) {
                            summon_morning(app);
                        } else {
                            toggle_drawer(app);
                        }
                    }
                })
                .build(),
        );
    }

    builder
        .plugin(tauri_plugin_updater::Builder::new().build())
        .invoke_handler(tauri::generate_handler![trace, quit, app_version, is_dev, report_bug, set_reserve, set_morning_mode, check_for_update, install_update, load_state, load_recovery_state, save_state])
        .setup(|app| {
            // Own the handle (clone) so it doesn't hold an immutable borrow of `app`
            // across the later `set_activation_policy` call (which needs `&mut app`).
            let handle = app.handle().clone();

            // --- Menu-bar (tray) icon + menu ---
            let toggle_item = MenuItemBuilder::with_id("toggle", "Show / Hide Buddy").build(app)?;
            let settings_item = MenuItemBuilder::with_id("settings", "Settings…").build(app)?;
            let report_item = MenuItemBuilder::with_id("report", "Report a bug…").build(app)?;
            let quit_item = MenuItemBuilder::with_id("quit", "Quit Buddy").build(app)?;
            let menu = MenuBuilder::new(app)
                .items(&[&toggle_item, &settings_item, &report_item])
                .separator()
                .items(&[&quit_item])
                .build()?;

            // Dev builds use a RED, non-template tray icon so a running dev instance is
            // unmistakable next to the installed (black, templated) release app.
            let dev = cfg!(debug_assertions);
            let tray_icon = if dev {
                tauri::image::Image::from_bytes(include_bytes!("../icons/tray-dev.png")).expect("tray icon")
            } else {
                tauri::image::Image::from_bytes(include_bytes!("../icons/tray.png")).expect("tray icon")
            };
            let _tray = TrayIconBuilder::with_id("buddy-tray")
                .icon(tray_icon)
                // Release icon is black-on-transparent → templated so macOS tints it for
                // light/dark menu bars. The dev (red) icon must NOT be templated, or the
                // red would be flattened to monochrome.
                .icon_as_template(!dev)
                .tooltip(if dev { "Dev Buddy" } else { "Buddy" })
                .menu(&menu)
                // A normal (left) click opens the menu. Buddy itself is summoned by
                // the right screen-edge, the global shortcut, or the menu's Show/Hide.
                .show_menu_on_left_click(true)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "toggle" => toggle_drawer(app),
                    "settings" => { let _ = app.emit("buddy://settings", ()); }
                    "report" => { let _ = app.emit("buddy://report-bug", ()); }
                    "quit" => app.exit(0),
                    _ => {}
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
                // Hidden show-off shortcut: ⌘⌥⌃M summons the morning planner from
                // anywhere (raises the window first — see `summon_morning`).
                if let Err(e) = handle.global_shortcut().register("Super+Alt+Control+KeyM") {
                    eprintln!("[buddy] could not register the morning (⌘⌥⌃M) shortcut: {e}");
                }
            }

            // Reveal on launch WITHOUT positioning — the web layer (nativeFit) owns
            // sizing/position so the full-screen morning isn't snapped back to the strip.
            if let Some(win) = handle.get_webview_window("main") {
                // Let Buddy appear OVER apps in native full-screen mode. The window is
                // already alwaysOnTop, but a floating window can't draw over a
                // full-screen Space unless its collection behaviour opts in — without
                // this, morning "flashes then hides behind" a full-screen browser.
                #[cfg(target_os = "macos")]
                allow_over_fullscreen(&win);
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
                    const DRAWER_W: f64 = 416.0; // the visible drawer's left edge (the window is wider for the shadow); hide when the cursor passes it
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
                                    // Bring Buddy to the front so its icons get hover/clicks
                                    // even when it reveals over another app.
                                    if let Some(w) = h.get_webview_window("main") {
                                        let _ = w.set_focus();
                                    }
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
