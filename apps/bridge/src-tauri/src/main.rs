use std::sync::Mutex;

use tauri::{
    AppHandle, Manager,
    menu::{CheckMenuItem, Menu, MenuItem},
    tray::TrayIconBuilder,
};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_shell::{
    ShellExt,
    process::{CommandChild, CommandEvent},
};

struct BridgeProcess(Mutex<Option<CommandChild>>);

fn focus_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

/// Spawns the sidecar, stores its handle in `BridgeProcess` (replacing
/// whatever was there), and listens for its events. On `Terminated` the
/// handle is cleared back to `None` so callers — namely `on_open_url` — can
/// tell a dead sidecar apart from a live one and respawn instead of
/// refocusing a window backed by nothing (see: port 46321 already bound by
/// a leftover process, so the freshly spawned child exits immediately).
fn spawn_sidecar<R: tauri::Runtime>(
    app: &AppHandle<R>,
    status: MenuItem<R>,
) -> Result<(), Box<dyn std::error::Error>> {
    let sidecar = app
        .shell()
        .sidecar("dmxtract_bridge")?
        .args(["--idle-timeout=0"]);
    let (mut events, process) = sidecar.spawn()?;
    if let Ok(mut guard) = app.state::<BridgeProcess>().0.lock() {
        *guard = Some(process);
    }

    let app_handle = app.clone();
    tauri::async_runtime::spawn(async move {
        while let Some(event) = events.recv().await {
            match event {
                CommandEvent::Stderr(bytes) => {
                    let line = String::from_utf8_lossy(&bytes);
                    let Some(payload) = line.strip_prefix("DMXTRACT_PAIRING\t") else {
                        continue;
                    };
                    let code = payload.trim();
                    let _ = status.set_text(format!("Approval requested · code {code}"));
                }
                CommandEvent::Terminated(_) => {
                    if let Ok(mut guard) = app_handle.state::<BridgeProcess>().0.lock() {
                        *guard = None;
                    }
                    let _ = status.set_text("Sidecar stopped · reopen the bridge to restart it");
                    break;
                }
                _ => {}
            }
        }
    });
    Ok(())
}

fn main() {
    tauri::Builder::default()
        // Registered first per tauri-plugin-single-instance's docs. A second
        // launch — e.g. the website's dmxtract:// link opening another
        // process — hits this callback instead of running main() again, so
        // the already-spawned sidecar never gets a duplicate fighting it for
        // the port. Bring the existing window forward instead.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            focus_main_window(app);
        }))
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_deep_link::init())
        .setup(|app| {
            #[cfg(any(windows, target_os = "linux"))]
            {
                // Bundled installers (NSIS/WiX, the Linux .desktop file)
                // register the scheme at install time from the
                // `plugins.deep-link` config in tauri.conf.json. This covers
                // dev builds and AppImages the bundler didn't register;
                // it's idempotent against an already-registered scheme.
                app.deep_link().register_all()?;
            }
            let status = MenuItem::with_id(
                app,
                "status",
                "Ready · no pairing request",
                false,
                None::<&str>,
            )?;
            app.manage(BridgeProcess(Mutex::new(None)));

            let open_handle = app.handle().clone();
            let open_status = status.clone();
            app.deep_link().on_open_url(move |_event| {
                // Any dmxtract:// URL means "open/ensure running" — no
                // payload is parsed and nothing from the URL is navigated
                // to or executed. Usually the sidecar spawned in setup()
                // below is still running and this just brings the window
                // forward, but if it died (e.g. its port was already bound
                // by a leftover process) `BridgeProcess` was cleared to
                // `None` by `spawn_sidecar`'s Terminated handler — respawn
                // it here rather than focusing a window backed by nothing.
                let needs_respawn = open_handle
                    .state::<BridgeProcess>()
                    .0
                    .lock()
                    .map(|guard| guard.is_none())
                    .unwrap_or(false);
                if needs_respawn {
                    let _ = spawn_sidecar(&open_handle, open_status.clone());
                }
                focus_main_window(&open_handle);
            });
            let autostart_enabled = app.autolaunch().is_enabled().unwrap_or(false);
            let autostart = CheckMenuItem::with_id(
                app,
                "autostart",
                "Start at login",
                true,
                autostart_enabled,
                None::<&str>,
            )?;
            let show = MenuItem::with_id(app, "show", "Show bridge window", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit and black out", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&status, &autostart, &show, &quit])?;

            TrayIconBuilder::new()
                .tooltip("DMXtract Bridge · output stopped")
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "autostart" => {
                        let manager = app.autolaunch();
                        // The plugin queries the OS for the real login-item
                        // state, so toggle off that reading rather than a
                        // locally cached flag, then read it back again
                        // instead of assuming the write succeeded.
                        let _ = if manager.is_enabled().unwrap_or(false) {
                            manager.disable()
                        } else {
                            manager.enable()
                        };
                        // Re-read regardless of whether the write above
                        // succeeded: muda already flipped the checkmark's
                        // visual state before this handler ran, so on a
                        // failure path (read-only home, MDM-managed Mac,
                        // locked profile) skipping this would leave the
                        // menu permanently out of sync with the OS.
                        let _ = autostart.set_checked(manager.is_enabled().unwrap_or(false));
                    }
                    "show" => focus_main_window(app),
                    "quit" => {
                        if let Some(process) = app
                            .state::<BridgeProcess>()
                            .0
                            .lock()
                            .ok()
                            .and_then(|mut child| child.take())
                        {
                            let _ = process.kill();
                        }
                        app.exit(0);
                    }
                    _ => {}
                })
                .build(app)?;

            // The tray icon is the thing meant to keep a forgotten session
            // from lingering (see README.md) — the sidecar's own idle
            // watchdog (api.rs `start_idle_watchdog`) has no way to tell the
            // tray shell it exited, so it would otherwise self-exit under a
            // tray icon that still claims to be ready, with no restart and
            // no menu item to recover short of Quit-and-relaunch. Disable
            // the sidecar's self-exit here and let Quit be the only way to
            // stop it while this app is running. `spawn_sidecar` also wires
            // up `on_open_url`'s respawn path for when the sidecar dies on
            // its own (e.g. its port was already bound).
            spawn_sidecar(app.handle(), status)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("DMXtract tray shell failed");
}
