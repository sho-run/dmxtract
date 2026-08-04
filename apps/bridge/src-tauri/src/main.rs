use std::sync::Mutex;

use tauri::{
    Manager,
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
};
use tauri_plugin_shell::{
    ShellExt,
    process::{CommandChild, CommandEvent},
};

struct BridgeProcess(Mutex<Option<CommandChild>>);

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let status = MenuItem::with_id(
                app,
                "status",
                "Ready · no pairing request",
                false,
                None::<&str>,
            )?;
            let show = MenuItem::with_id(app, "show", "Show bridge window", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit and black out", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&status, &show, &quit])?;

            TrayIconBuilder::new()
                .tooltip("DMXtract Bridge · output stopped")
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
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

            let sidecar = app.shell().sidecar("dmxtract_bridge")?;
            let (mut events, process) = sidecar.spawn()?;
            app.manage(BridgeProcess(Mutex::new(Some(process))));

            tauri::async_runtime::spawn(async move {
                while let Some(event) = events.recv().await {
                    let CommandEvent::Stderr(bytes) = event else {
                        continue;
                    };
                    let line = String::from_utf8_lossy(&bytes);
                    let Some(payload) = line.strip_prefix("DMXTRACT_PAIRING\t") else {
                        continue;
                    };
                    let code = payload.trim();
                    let _ = status.set_text(format!("Approval requested · code {code}"));
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("DMXtract tray shell failed");
}
