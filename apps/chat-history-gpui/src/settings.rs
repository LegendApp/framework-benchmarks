use std::{env, fs, path::PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub appearance: String,
    pub load_images: bool,
    pub recent_chat_limit: usize,
    pub restore_selection: bool,
    pub selected_id: Option<String>,
    pub show_performance_metrics: bool,
}

impl Default for Settings {
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

impl Settings {
    pub fn load() -> Self {
        fs::read(settings_path())
            .ok()
            .and_then(|source| serde_json::from_slice(&source).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) {
        let path = settings_path();
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        if let Ok(source) = serde_json::to_vec_pretty(self) {
            let _ = fs::write(path, source);
        }
    }
}

fn settings_path() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default()
        .join("Library/Application Support/Legend Chat History GPUI/settings.json")
}
