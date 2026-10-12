use std::{
    env, fs,
    io::Write,
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

use serde::Deserialize;

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Target {
    pub id: String,
    pub provider: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    appearance: Option<String>,
    load_images: bool,
    switch_delay_ms: u64,
    top_delay_ms: u64,
    targets: Vec<Target>,
    version: usize,
}

#[derive(Clone)]
pub struct Benchmark {
    pub appearance: Option<String>,
    pub load_images: bool,
    pub switch_delay_ms: u64,
    pub top_delay_ms: u64,
    pub targets: Vec<Target>,
    events_path: Option<PathBuf>,
}

impl Benchmark {
    pub fn load() -> Result<Option<Self>, String> {
        let Some(config_path) = env::var_os("CHAT_HISTORY_BENCHMARK_CONFIG") else {
            return Ok(None);
        };
        let source = fs::read_to_string(config_path)
            .map_err(|error| format!("Could not read benchmark manifest: {error}"))?;
        let manifest: Manifest = serde_json::from_str(&source)
            .map_err(|error| format!("Invalid benchmark manifest: {error}"))?;
        if manifest.version != 2 || manifest.targets.len() != 2 {
            return Err("Unsupported chat history benchmark manifest".into());
        }
        Ok(Some(Self {
            appearance: manifest.appearance,
            load_images: manifest.load_images,
            switch_delay_ms: manifest.switch_delay_ms,
            top_delay_ms: manifest.top_delay_ms,
            targets: manifest.targets,
            events_path: env::var_os("CHAT_HISTORY_BENCHMARK_EVENTS").map(PathBuf::from),
        }))
    }

    pub fn emit(&self, mut event: serde_json::Value) -> Result<(), String> {
        append_event(self.events_path.as_ref(), &mut event)
    }
}

pub fn emit_window_shown() {
    let path = env::var_os("CHAT_HISTORY_BENCHMARK_EVENTS").map(PathBuf::from);
    let _ = append_event(
        path.as_ref(),
        &mut serde_json::json!({ "name": "windowShown" }),
    );
}

fn append_event(path: Option<&PathBuf>, event: &mut serde_json::Value) -> Result<(), String> {
    let Some(path) = path else {
        return Ok(());
    };
    event
        .as_object_mut()
        .ok_or("Benchmark event must be an object")?
        .insert("timestampMs".into(), timestamp_ms().into());
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|error| format!("Could not open benchmark event log: {error}"))?;
    writeln!(file, "{event}").map_err(|error| format!("Could not write benchmark event: {error}"))
}

fn timestamp_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}
