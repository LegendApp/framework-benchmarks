use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatHistorySettings {
    appearance: String,
    load_images: bool,
    recent_chat_limit: usize,
    restore_selection: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    selected_id: Option<String>,
    show_performance_metrics: bool,
}

impl Default for ChatHistorySettings {
    fn default() -> Self {
        Self {
            appearance: "system".into(),
            load_images: true,
            recent_chat_limit: 20,
            restore_selection: true,
            selected_id: None,
            show_performance_metrics: true,
        }
    }
}

impl ChatHistorySettings {
    fn normalized(mut self) -> Self {
        if !matches!(self.appearance.as_str(), "dark" | "light" | "system") {
            self.appearance = "system".into();
        }
        if !matches!(self.recent_chat_limit, 20 | 50 | 100) {
            self.recent_chat_limit = 20;
        }
        if !self.restore_selection {
            self.selected_id = None;
        }
        self
    }
}

fn read_at(path: &Path) -> ChatHistorySettings {
    fs::read(path)
        .ok()
        .and_then(|source| serde_json::from_slice::<ChatHistorySettings>(&source).ok())
        .unwrap_or_default()
        .normalized()
}

fn write_at(path: &Path, settings: ChatHistorySettings) -> Result<(), String> {
    let settings = settings.normalized();
    let parent = path
        .parent()
        .ok_or("Settings path has no parent directory")?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("Failed to create settings directory: {error}"))?;
    let source = serde_json::to_vec_pretty(&settings)
        .map_err(|error| format!("Failed to encode settings: {error}"))?;
    fs::write(path, source).map_err(|error| format!("Failed to save settings: {error}"))
}

fn settings_path(app: &AppHandle) -> Result<std::path::PathBuf, String> {
    app.path()
        .app_config_dir()
        .map(|path| path.join("settings.json"))
        .map_err(|error| format!("Failed to resolve settings directory: {error}"))
}

pub fn get_settings(app: &AppHandle) -> Result<ChatHistorySettings, String> {
    Ok(read_at(&settings_path(app)?))
}

pub fn save_settings(app: &AppHandle, settings: ChatHistorySettings) -> Result<(), String> {
    write_at(&settings_path(app)?, settings)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_and_persists_settings() {
        let root =
            std::env::temp_dir().join(format!("legend-tauri-settings-{}", std::process::id()));
        let path = root.join("settings.json");
        let settings = ChatHistorySettings {
            appearance: "dark".into(),
            load_images: false,
            recent_chat_limit: 100,
            restore_selection: true,
            selected_id: Some("codex:example".into()),
            show_performance_metrics: false,
        };
        write_at(&path, settings.clone()).expect("settings should save");
        assert_eq!(read_at(&path), settings);
        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn invalid_values_use_stable_defaults() {
        let settings = ChatHistorySettings {
            appearance: "sepia".into(),
            recent_chat_limit: 500,
            ..ChatHistorySettings::default()
        }
        .normalized();
        assert_eq!(settings.appearance, "system");
        assert_eq!(settings.recent_chat_limit, 20);
    }
}
