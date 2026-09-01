mod settings;

use std::{
    env, fs,
    io::Write,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use chat_history_rust::{
    CatalogResult, ChatDocument, get_recent_chat_catalog, open_chat_file, user_home,
};
use settings::ChatHistorySettings;
use tauri::Manager;

fn benchmark_timestamp_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

fn append_benchmark_event(mut event: serde_json::Value) -> Result<(), String> {
    let Some(path) = env::var_os("CHAT_HISTORY_BENCHMARK_EVENTS") else {
        return Ok(());
    };
    let object = event
        .as_object_mut()
        .ok_or_else(|| "Benchmark event must be an object".to_string())?;
    object.insert("timestampMs".into(), benchmark_timestamp_ms().into());
    let mut file = fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(path)
        .map_err(|error| format!("Could not open benchmark event log: {error}"))?;
    writeln!(file, "{event}").map_err(|error| format!("Could not write benchmark event: {error}"))
}

#[tauri::command]
fn get_benchmark_config() -> Result<Option<serde_json::Value>, String> {
    let Some(path) = env::var_os("CHAT_HISTORY_BENCHMARK_CONFIG") else {
        return Ok(None);
    };
    let source = fs::read_to_string(path)
        .map_err(|error| format!("Could not read benchmark manifest: {error}"))?;
    serde_json::from_str(&source)
        .map(Some)
        .map_err(|error| format!("Invalid benchmark manifest: {error}"))
}

#[tauri::command]
fn emit_benchmark_event(event: serde_json::Value) -> Result<(), String> {
    append_benchmark_event(event)
}

#[tauri::command]
async fn get_recent_chats(limit: usize) -> Result<CatalogResult, String> {
    tauri::async_runtime::spawn_blocking(move || Ok(get_recent_chat_catalog(limit, &user_home()?)))
        .await
        .map_err(|error| format!("Transcript catalog task failed: {error}"))?
}

fn allowed_root(home: &Path, provider: &str, path: &Path) -> bool {
    match provider {
        "codex" => [
            home.join(".codex/sessions"),
            home.join(".codex/archived_sessions"),
        ]
        .iter()
        .any(|root| path.starts_with(root)),
        "claude" => path.starts_with(home.join(".claude/projects")),
        _ => false,
    }
}

#[tauri::command]
async fn open_chat(provider: String, path: String) -> Result<ChatDocument, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let home = user_home()?;
        let path = PathBuf::from(path)
            .canonicalize()
            .map_err(|error| format!("Invalid transcript path: {error}"))?;
        if !allowed_root(&home, &provider, &path)
            || path.extension().and_then(|value| value.to_str()) != Some("jsonl")
        {
            return Err("Transcript path is outside the provider history directory".into());
        }
        open_chat_file(&provider, &path)
    })
    .await
    .map_err(|error| format!("Transcript parser task failed: {error}"))?
}

#[tauri::command]
fn get_settings(app: tauri::AppHandle) -> Result<ChatHistorySettings, String> {
    settings::get_settings(&app)
}

#[tauri::command]
fn save_settings(app: tauri::AppHandle, settings: ChatHistorySettings) -> Result<(), String> {
    settings::save_settings(&app, settings)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let window = match app.get_webview_window("main") {
                Some(window) => window,
                None => tauri::WebviewWindowBuilder::new(
                    app,
                    "main",
                    tauri::WebviewUrl::App("index.html".into()),
                )
                .title("Legend Chat History — Tauri")
                .inner_size(1280.0, 720.0)
                .min_inner_size(640.0, 460.0)
                .build()?,
            };
            window.show()?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            emit_benchmark_event,
            get_benchmark_config,
            get_recent_chats,
            get_settings,
            open_chat,
            save_settings
        ])
        .build(tauri::generate_context!())
        .expect("failed to build Tauri chat history benchmark");
    app.run(|app, event| {
        if matches!(event, tauri::RunEvent::Ready) {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
            let _ = append_benchmark_event(serde_json::json!({ "name": "windowShown" }));
        }
    });
}
