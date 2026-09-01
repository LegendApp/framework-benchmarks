use std::{
    collections::{HashMap, HashSet},
    env, fs,
    io::{BufRead, BufReader, Read},
    path::{Path, PathBuf},
    time::{Instant, UNIX_EPOCH},
};

use chrono::{DateTime, Local, Utc};
use serde_json::Value;

use crate::model::{CatalogResult, ChatSummary};

#[derive(Clone, Default)]
struct Metadata {
    title: String,
    updated_at: f64,
}

struct Candidate {
    indexed: bool,
    summary: ChatSummary,
}

fn timestamp(value: Option<&Value>) -> f64 {
    if let Some(value) = value.and_then(Value::as_f64) {
        return value;
    }
    value
        .and_then(Value::as_str)
        .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
        .map(|value| value.timestamp_millis() as f64)
        .unwrap_or(0.0)
}

fn walk_jsonl(root: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let mut directories = vec![root.to_path_buf()];
    while let Some(directory) = directories.pop() {
        let Ok(entries) = fs::read_dir(directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                directories.push(path);
            } else if path
                .extension()
                .is_some_and(|extension| extension == "jsonl")
            {
                files.push(path);
            }
        }
    }
    files
}

fn session_id(path: &Path) -> String {
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("");
    if stem.len() >= 36 {
        stem[stem.len() - 36..].into()
    } else {
        stem.into()
    }
}

fn modified_at(path: &Path) -> f64 {
    fs::metadata(path)
        .and_then(|value| value.modified())
        .ok()
        .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
        .map(|value| value.as_secs_f64() * 1000.0)
        .unwrap_or(0.0)
}

fn fallback_title(provider: &str, updated_at: f64) -> String {
    let date = DateTime::<Utc>::from_timestamp_millis(updated_at as i64)
        .map(|date| date.with_timezone(&Local).format("%b %-d").to_string())
        .unwrap_or_else(|| "Unknown date".into());
    format!(
        "{} chat — {date}",
        if provider == "codex" {
            "Codex"
        } else {
            "Claude"
        }
    )
}

fn load_codex_metadata(home: &Path) -> HashMap<String, Metadata> {
    let mut metadata = HashMap::new();
    let Ok(file) = fs::File::open(home.join(".codex/session_index.jsonl")) else {
        return metadata;
    };
    for line in BufReader::new(file).lines().map_while(Result::ok) {
        let Ok(Value::Object(record)) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let id = record.get("id").and_then(Value::as_str).unwrap_or("");
        if !id.is_empty() {
            metadata.insert(
                id.into(),
                Metadata {
                    title: record
                        .get("thread_name")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .into(),
                    updated_at: timestamp(record.get("updated_at")),
                },
            );
        }
    }
    metadata
}

fn load_claude_metadata(root: &Path) -> HashMap<String, Metadata> {
    let mut metadata = HashMap::new();
    let mut directories = vec![root.to_path_buf()];
    while let Some(directory) = directories.pop() {
        let Ok(entries) = fs::read_dir(directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                directories.push(path);
                continue;
            }
            if path.file_name().and_then(|value| value.to_str()) != Some("sessions-index.json") {
                continue;
            }
            let Some(Value::Object(index)) = fs::read_to_string(path)
                .ok()
                .and_then(|source| serde_json::from_str::<Value>(&source).ok())
            else {
                continue;
            };
            for item in index
                .get("entries")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                let Some(item) = item.as_object() else {
                    continue;
                };
                let full_path = item.get("fullPath").and_then(Value::as_str).unwrap_or("");
                let id = item.get("sessionId").and_then(Value::as_str).unwrap_or("");
                let value = Metadata {
                    title: item
                        .get("summary")
                        .and_then(Value::as_str)
                        .or_else(|| item.get("firstPrompt").and_then(Value::as_str))
                        .unwrap_or("")
                        .into(),
                    updated_at: timestamp(item.get("modified"))
                        .max(timestamp(item.get("fileMtime"))),
                };
                if !full_path.is_empty() {
                    metadata.insert(full_path.into(), value.clone());
                }
                if !id.is_empty() {
                    metadata.insert(id.into(), value);
                }
            }
        }
    }
    metadata
}

fn is_codex_subagent(path: &Path) -> bool {
    let Ok(mut file) = fs::File::open(path) else {
        return false;
    };
    let mut source = String::new();
    if file
        .by_ref()
        .take(64 * 1024)
        .read_to_string(&mut source)
        .is_err()
    {
        return false;
    }
    let first = source.lines().next().unwrap_or("");
    serde_json::from_str::<Value>(first)
        .ok()
        .and_then(|root| root.pointer("/payload/source/subagent").cloned())
        .is_some()
}

pub fn get_recent_chat_catalog(limit: usize, home: &Path) -> CatalogResult {
    let started = Instant::now();
    let limit = limit.min(100);
    if limit == 0 {
        return CatalogResult {
            native_total_ms: started.elapsed().as_secs_f64() * 1000.0,
            summaries: Vec::new(),
        };
    }
    let codex_metadata = load_codex_metadata(home);
    let claude_root = home.join(".claude/projects");
    let claude_metadata = load_claude_metadata(&claude_root);
    let mut candidates = Vec::new();
    for path in walk_jsonl(&home.join(".codex/sessions"))
        .into_iter()
        .chain(walk_jsonl(&home.join(".codex/archived_sessions")))
    {
        let id = session_id(&path);
        let found = codex_metadata.get(&id);
        let updated_at = found
            .map(|value| value.updated_at)
            .filter(|value| *value > 0.0)
            .unwrap_or_else(|| modified_at(&path));
        candidates.push(Candidate {
            indexed: found.is_some(),
            summary: ChatSummary {
                id: format!("codex:{id}"),
                path: path.to_string_lossy().into_owned(),
                provider: "codex".into(),
                title: found
                    .map(|value| value.title.clone())
                    .filter(|value| !value.is_empty())
                    .unwrap_or_else(|| fallback_title("codex", updated_at)),
                updated_at,
            },
        });
    }
    for path in walk_jsonl(&claude_root) {
        if path
            .components()
            .any(|part| part.as_os_str() == "subagents")
            || path
                .file_name()
                .and_then(|value| value.to_str())
                .is_some_and(|name| name.starts_with("agent-"))
        {
            continue;
        }
        let id = session_id(&path);
        let path_text = path.to_string_lossy().into_owned();
        let found = claude_metadata
            .get(&path_text)
            .or_else(|| claude_metadata.get(&id));
        let updated_at = found
            .map(|value| value.updated_at)
            .filter(|value| *value > 0.0)
            .unwrap_or_else(|| modified_at(&path));
        candidates.push(Candidate {
            indexed: true,
            summary: ChatSummary {
                id: format!("claude:{id}"),
                path: path_text,
                provider: "claude".into(),
                title: found
                    .map(|value| value.title.clone())
                    .filter(|value| !value.is_empty())
                    .unwrap_or_else(|| fallback_title("claude", updated_at)),
                updated_at,
            },
        });
    }
    candidates.sort_by(|left, right| {
        right
            .summary
            .updated_at
            .total_cmp(&left.summary.updated_at)
            .then_with(|| left.summary.id.cmp(&right.summary.id))
    });
    let mut summaries = Vec::new();
    let mut seen = HashSet::new();
    for candidate in candidates {
        if !seen.insert(candidate.summary.id.clone()) {
            continue;
        }
        if !candidate.indexed && is_codex_subagent(Path::new(&candidate.summary.path)) {
            continue;
        }
        summaries.push(candidate.summary);
        if summaries.len() == limit {
            break;
        }
    }
    CatalogResult {
        native_total_ms: started.elapsed().as_secs_f64() * 1000.0,
        summaries,
    }
}

pub fn user_home() -> Result<PathBuf, String> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is unavailable".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temporary_home() -> PathBuf {
        let root = env::temp_dir().join(format!(
            "legend-tauri-catalog-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn empty_limit_avoids_catalog_work() {
        let root = temporary_home();
        let result = get_recent_chat_catalog(0, &root);
        fs::remove_dir_all(root).unwrap();
        assert!(result.summaries.is_empty());
    }

    #[test]
    fn discovers_indexed_sessions_and_excludes_subagents() {
        let root = temporary_home();
        let codex_root = root.join(".codex/sessions");
        let claude_root = root.join(".claude/projects/demo");
        fs::create_dir_all(&codex_root).unwrap();
        fs::create_dir_all(&claude_root).unwrap();

        let codex_id = "11111111-1111-1111-1111-111111111111";
        fs::write(
            codex_root.join(format!("rollout-2026-01-01-{codex_id}.jsonl")),
            "{\"body\":\"catalog must not parse this\"}\n",
        )
        .unwrap();
        fs::write(
            root.join(".codex/session_index.jsonl"),
            format!("{{\"id\":\"{codex_id}\",\"thread_name\":\"Indexed Codex\",\"updated_at\":\"2026-01-01T10:00:00Z\"}}\n"),
        )
        .unwrap();

        let subagent_id = "22222222-2222-2222-2222-222222222222";
        fs::write(
            codex_root.join(format!("rollout-2026-01-02-{subagent_id}.jsonl")),
            format!("{{\"payload\":{{\"source\":{{\"subagent\":{{\"thread_spawn\":{{\"parent_thread_id\":\"{codex_id}\"}}}}}}}},\"type\":\"session_meta\"}}\n"),
        )
        .unwrap();

        let claude_id = "33333333-3333-3333-3333-333333333333";
        let claude_path = claude_root.join(format!("{claude_id}.jsonl"));
        fs::write(
            &claude_path,
            "{\"body\":\"catalog must not parse this either\"}\n",
        )
        .unwrap();
        fs::write(
            claude_root.join("sessions-index.json"),
            serde_json::json!({
                "version": 1,
                "entries": [{
                    "sessionId": claude_id,
                    "fullPath": claude_path,
                    "summary": "Indexed Claude",
                    "modified": "2026-01-03T10:00:00Z"
                }]
            })
            .to_string(),
        )
        .unwrap();

        let result = get_recent_chat_catalog(20, &root);
        fs::remove_dir_all(root).unwrap();
        assert_eq!(
            result
                .summaries
                .iter()
                .map(|summary| summary.title.as_str())
                .collect::<Vec<_>>(),
            ["Indexed Claude", "Indexed Codex"]
        );
        assert!(
            !result
                .summaries
                .iter()
                .any(|summary| summary.id == format!("codex:{subagent_id}"))
        );
    }
}
