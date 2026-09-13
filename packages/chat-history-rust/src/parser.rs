use std::{
    collections::{HashMap, HashSet},
    fs,
    path::Path,
    time::Instant,
};

use crate::{
    DeferredText,
    json_range::{Map, Value},
};
use chrono::DateTime;
use std::{ops::Range, sync::Arc};

use crate::model::{ChatDocument, ChatFileChange, ChatRow, NativeTiming};

#[derive(Clone, Default)]
struct WorkingRow {
    row: ChatRow,
    call_id: String,
    started_at_ms: f64,
    ended_at_ms: f64,
}

struct ClaudeRecord {
    root: Map<String, Value>,
    uuid: String,
    parent_uuid: String,
    record_type: String,
    sidechain: bool,
    timestamp_ms: f64,
}

fn object(value: Option<&Value>) -> Option<&Map<String, Value>> {
    value?.as_object()
}

fn text(value: Option<&Value>) -> &str {
    value.and_then(Value::as_str).unwrap_or("")
}

fn deferred_text(value: Option<&Value>) -> DeferredText {
    match value.filter(|value| value.is_string()) {
        Some(value) => {
            let value = value.clone();
            DeferredText::new(value.text_nonempty(), move || value.decode_string())
        }
        None => DeferredText::default(),
    }
}

fn timestamp(value: Option<&Value>) -> f64 {
    DateTime::parse_from_rfc3339(text(value))
        .map(|date| date.timestamp_millis() as f64)
        .unwrap_or(0.0)
}

fn empty_row(kind: &str, timestamp_ms: f64) -> WorkingRow {
    WorkingRow {
        row: ChatRow {
            kind: kind.into(),
            ..ChatRow::default()
        },
        started_at_ms: timestamp_ms,
        ended_at_ms: timestamp_ms,
        ..WorkingRow::default()
    }
}

fn join_text(parts: &[DeferredText]) -> DeferredText {
    let parts = parts.to_vec();
    DeferredText::new(parts.iter().any(|part| !part.is_empty()), move || {
        parts
            .iter()
            .filter(|part| !part.is_empty())
            .map(|part| part.decode_uncached())
            .collect::<Vec<_>>()
            .join("\n\n")
    })
}

fn append_message(
    rows: &mut Vec<WorkingRow>,
    kind: &str,
    parts: Vec<DeferredText>,
    image_sources: Vec<String>,
    has_image_placeholder: bool,
    timestamp_ms: f64,
) {
    let markdown = join_text(&parts);
    if !markdown.is_empty() || !image_sources.is_empty() || has_image_placeholder {
        let mut row = empty_row(kind, timestamp_ms);
        row.row.markdown = markdown;
        row.row.image_sources = image_sources;
        row.row.has_image_placeholder = has_image_placeholder;
        rows.push(row);
    }
}

fn append_tool(
    rows: &mut Vec<WorkingRow>,
    tool_rows: &mut HashMap<String, usize>,
    call_id: String,
    name: String,
    preview: DeferredText,
    timestamp_ms: f64,
) -> usize {
    let mut row = empty_row("tool", timestamp_ms);
    row.call_id = call_id.clone();
    row.row.tool_name = if name.is_empty() { "Tool".into() } else { name };
    row.row.tool_preview = preview;
    row.row.tool_status = "unknown".into();
    rows.push(row);
    let index = rows.len() - 1;
    if !call_id.is_empty() {
        tool_rows.insert(call_id, index);
    }
    index
}

fn apply_tool_result(
    rows: &mut Vec<WorkingRow>,
    tool_rows: &mut HashMap<String, usize>,
    call_id: String,
    preview: DeferredText,
    failed: bool,
    timestamp_ms: f64,
) {
    let index = tool_rows.get(&call_id).copied().unwrap_or_else(|| {
        append_tool(
            rows,
            tool_rows,
            call_id,
            "Tool".into(),
            DeferredText::default(),
            timestamp_ms,
        )
    });
    let row = &mut rows[index];
    row.row.tool_status = if failed { "failed" } else { "completed" }.into();
    row.ended_at_ms = row.ended_at_ms.max(timestamp_ms);
    if !preview.is_empty() {
        row.row.tool_preview = preview;
    }
}

fn visible_user_markdown(row: &WorkingRow, markdown: String) -> String {
    const FILES_HEADING: &str = "# Files mentioned by the user:";
    const REQUEST_HEADING: &str = "## My request for Codex:";
    let trimmed = markdown.trim_start_matches(['\r', '\n']);
    if row.row.kind == "user"
        && (!row.row.image_sources.is_empty() || row.row.has_image_placeholder)
        && trimmed.starts_with(FILES_HEADING)
        && let Some(request) = trimmed.find(REQUEST_HEADING)
    {
        return trimmed[request + REQUEST_HEADING.len()..]
            .trim_start_matches(['\r', '\n'])
            .to_string();
    }
    markdown
}

fn is_directive(line: &str) -> bool {
    [
        "::git-stage{",
        "::git-commit{",
        "::git-create-branch{",
        "::git-push{",
        "::git-create-pr{",
        "::created-thread{",
        "::code-comment{",
    ]
    .iter()
    .any(|prefix| line.trim().starts_with(prefix))
}

fn visible_assistant_markdown(kind: &str, markdown: String) -> String {
    if kind != "assistant" {
        return markdown;
    }
    let mut visible = Vec::new();
    let mut in_code_fence = false;
    let mut in_memory_citation = false;
    for line in markdown.lines() {
        let trimmed = line.trim();
        if in_memory_citation || (!in_code_fence && trimmed.starts_with("<oai-mem-citation>")) {
            in_memory_citation = !trimmed.contains("</oai-mem-citation>");
        } else if in_code_fence || !is_directive(line) {
            visible.push(line);
        }
        if !in_memory_citation && (trimmed.starts_with("```") || trimmed.starts_with("~~~")) {
            in_code_fence = !in_code_fence;
        }
    }
    visible
        .join("\n")
        .trim_end_matches(['\r', '\n'])
        .to_string()
}

fn tool_activity_label(row: &WorkingRow) -> String {
    let name = row.row.tool_name.to_lowercase();
    let mut label = if ["exec", "shell", "command", "bash"]
        .iter()
        .any(|part| name.contains(part))
    {
        "Ran a command".into()
    } else if name.contains("agent") {
        "Worked with an agent".into()
    } else if ["patch", "write", "edit"]
        .iter()
        .any(|part| name.contains(part))
    {
        "Edited files".into()
    } else if ["read", "open", "find", "glob", "grep"]
        .iter()
        .any(|part| name.contains(part))
    {
        "Read files".into()
    } else if ["web", "search", "browser"]
        .iter()
        .any(|part| name.contains(part))
    {
        "Searched the web".into()
    } else if name.contains("image") {
        "Created an image".into()
    } else if name.is_empty() {
        "Used a tool".into()
    } else {
        format!("Used {}", name.replace(['_', '-'], " "))
    };
    if row.row.tool_status == "failed" {
        label.push_str(" (failed)");
    }
    label
}

fn work_label(rows: &[WorkingRow]) -> String {
    let started = rows
        .iter()
        .filter(|row| row.started_at_ms > 0.0)
        .map(|row| row.started_at_ms)
        .reduce(f64::min);
    let ended = rows
        .iter()
        .filter(|row| row.ended_at_ms > 0.0)
        .map(|row| row.ended_at_ms)
        .reduce(f64::max);
    let (Some(started), Some(ended)) = (started, ended) else {
        return "Worked".into();
    };
    let elapsed = (((ended - started) / 1000.0).round() as usize).max(1);
    let hours = elapsed / 3600;
    let minutes = (elapsed % 3600) / 60;
    let seconds = elapsed % 60;
    let duration = if hours > 0 {
        if minutes > 0 {
            format!("{hours}h {minutes}m")
        } else {
            format!("{hours}h")
        }
    } else if minutes > 0 {
        if seconds > 0 {
            format!("{minutes}m {seconds}s")
        } else {
            format!("{minutes}m")
        }
    } else {
        format!("{seconds}s")
    };
    format!("Worked for {duration}")
}

fn work_preview(rows: &[WorkingRow]) -> String {
    let mut output = Vec::new();
    let mut activities: Vec<String> = Vec::new();
    let flush = |output: &mut Vec<String>, activities: &mut Vec<String>| {
        if !activities.is_empty() {
            let mut summary = activities[0].clone();
            for activity in &activities[1..] {
                let mut continuation = activity.clone();
                if let Some(first) = continuation.get_mut(0..1) {
                    first.make_ascii_lowercase();
                }
                summary.push_str(", ");
                summary.push_str(&continuation);
            }
            output.push(summary);
            activities.clear();
        }
    };
    for row in rows {
        if row.row.kind == "tool" {
            let activity = tool_activity_label(row);
            if !activities.contains(&activity) {
                activities.push(activity);
            }
        } else {
            flush(&mut output, &mut activities);
            if !row.row.markdown.is_empty() {
                output.push(
                    row.row
                        .markdown
                        .decode_uncached()
                        .chars()
                        .take(4096)
                        .collect(),
                );
            }
            if row.row.has_image_placeholder {
                output.push("Image or attachment omitted".into());
            }
        }
    }
    flush(&mut output, &mut activities);
    output.join("\n\n").chars().take(64 * 1024).collect()
}

fn finalize(mut row: WorkingRow, index: usize) -> ChatRow {
    row.row.id = format!("row:{index}");
    let original = row.clone();
    row.row.markdown = DeferredText::new(!original.row.markdown.is_empty(), move || {
        visible_assistant_markdown(
            &original.row.kind,
            visible_user_markdown(&original, original.row.markdown.decode_uncached()),
        )
    });
    row.row
}

fn display_rows(rows: Vec<WorkingRow>) -> Vec<ChatRow> {
    let mut result = Vec::new();
    let mut index = 0;
    while index < rows.len() {
        if rows[index].row.kind == "user" {
            result.push(finalize(rows[index].clone(), result.len()));
            index += 1;
            continue;
        }
        let mut turn_end = index;
        let mut last_tool = None;
        while turn_end < rows.len() && rows[turn_end].row.kind != "user" {
            if rows[turn_end].row.kind == "tool" {
                last_tool = Some(turn_end);
            }
            turn_end += 1;
        }
        if let Some(last_tool) = last_tool {
            let grouped = &rows[index..=last_tool];
            let mut work = empty_row("tool", 0.0);
            work.row.tool_name = work_label(grouped);
            let preview_rows = grouped.to_vec();
            work.row.tool_preview = DeferredText::new(true, move || work_preview(&preview_rows));
            work.row.tool_status = if grouped
                .iter()
                .any(|row| row.row.kind == "tool" && row.row.tool_status == "failed")
            {
                "failed"
            } else if grouped
                .iter()
                .any(|row| row.row.kind == "tool" && row.row.tool_status != "completed")
            {
                "unknown"
            } else {
                "completed"
            }
            .into();
            result.push(finalize(work, result.len()));
            index = last_tool + 1;
        } else {
            result.push(finalize(rows[index].clone(), result.len()));
            index += 1;
        }
    }
    result
}

fn count_diff_lines(diff: &str) -> (usize, usize) {
    let (mut additions, mut deletions, mut in_hunk) = (0, 0, false);
    for line in diff.lines() {
        if line.starts_with("@@") {
            in_hunk = true;
        } else if in_hunk && line.starts_with('+') {
            additions += 1;
        } else if in_hunk && line.starts_with('-') {
            deletions += 1;
        }
    }
    (additions, deletions)
}

fn count_content_lines(content: &str) -> usize {
    content.bytes().filter(|byte| *byte == b'\n').count()
        + usize::from(!content.is_empty() && !content.ends_with('\n'))
}

fn parse_message_content(
    payload: &Map<String, Value>,
    warnings: &mut usize,
) -> (Vec<DeferredText>, bool) {
    let mut parts = Vec::new();
    let mut has_image = false;
    match payload.get("content") {
        Some(value) if value.is_string() => parts.push(deferred_text(Some(value))),
        Some(value) if value.as_array().is_some() => {
            let content = value.as_array().unwrap();
            for raw_block in content {
                let Some(block) = raw_block.as_object() else {
                    continue;
                };
                match text(block.get("type")) {
                    "input_text" | "output_text" | "text" => {
                        parts.push(deferred_text(block.get("text")))
                    }
                    "input_image" | "image" => has_image = true,
                    "" => {}
                    _ => *warnings += 1,
                }
            }
        }
        Some(_) => *warnings += 1,
        None => {}
    }
    (parts, has_image)
}

fn parse_codex(source: &Arc<String>, lines: &[Range<usize>]) -> (Vec<ChatRow>, usize) {
    let mut rows = Vec::new();
    let mut tool_rows = HashMap::new();
    let mut warnings = 0;
    let mut cwd = String::new();
    let mut saw_event_user = false;
    let mut pending_turn = String::new();
    let mut pending_files: Vec<ChatFileChange> = Vec::new();
    let append_files = |rows: &mut Vec<WorkingRow>, files: &mut Vec<ChatFileChange>| {
        if !files.is_empty() {
            let mut row = empty_row("files", 0.0);
            row.row.file_changes = std::mem::take(files);
            rows.push(row);
        }
    };

    for line in lines {
        let Some(root_value) = Value::parse(source.clone(), line.clone()) else {
            warnings += 1;
            continue;
        };
        let Some(root) = root_value.as_object() else {
            warnings += 1;
            continue;
        };
        let record_type = text(root.get("type"));
        let payload = object(root.get("payload"));
        let timestamp_ms = timestamp(root.get("timestamp"));
        if record_type.is_empty() || !root.contains_key("payload") {
            warnings += 1;
            continue;
        }
        if record_type == "compacted" {
            continue;
        }
        if matches!(record_type, "session_meta" | "turn_context") {
            if let Some(next) = payload
                .map(|value| text(value.get("cwd")))
                .filter(|value| !value.is_empty())
            {
                cwd = next.into();
            }
            continue;
        }
        if record_type == "event_msg" {
            if let Some(payload) = payload {
                match text(payload.get("type")) {
                    "user_message" => {
                        saw_event_user = true;
                        append_files(&mut rows, &mut pending_files);
                        pending_turn.clear();
                        let message = deferred_text(payload.get("message"));
                        if message.is_empty() {
                            warnings += 1;
                        }
                        let local = payload
                            .get("local_images")
                            .and_then(Value::as_array)
                            .into_iter()
                            .flatten()
                            .filter_map(Value::as_str)
                            .map(str::to_string)
                            .collect::<Vec<_>>();
                        let mut images = local;
                        let mut placeholder = false;
                        for image in payload
                            .get("images")
                            .and_then(Value::as_array)
                            .into_iter()
                            .flatten()
                        {
                            let image = image.as_str().unwrap_or("");
                            if image.is_empty() || image.len() > 8192 {
                                placeholder = true;
                            } else {
                                images.push(image.into());
                            }
                        }
                        append_message(
                            &mut rows,
                            "user",
                            vec![message],
                            images,
                            placeholder,
                            timestamp_ms,
                        );
                    }
                    "patch_apply_end"
                        if payload.get("success").and_then(Value::as_bool) == Some(true) =>
                    {
                        let turn = text(payload.get("turn_id"));
                        if !pending_turn.is_empty() && !turn.is_empty() && pending_turn != turn {
                            append_files(&mut rows, &mut pending_files);
                        }
                        pending_turn = turn.into();
                        if let Some(changes) = object(payload.get("changes")) {
                            for (path, raw_change) in changes {
                                let Some(change) = raw_change.as_object() else {
                                    warnings += 1;
                                    continue;
                                };
                                let change_type = text(change.get("type"));
                                let counts = match change_type {
                                    "update" => change
                                        .get("unified_diff")
                                        .and_then(Value::as_str)
                                        .map(count_diff_lines),
                                    "add" => change
                                        .get("content")
                                        .and_then(Value::as_str)
                                        .map(|value| (count_content_lines(value), 0)),
                                    "delete" => change
                                        .get("content")
                                        .and_then(Value::as_str)
                                        .map(|value| (0, count_content_lines(value))),
                                    _ => None,
                                };
                                let Some((additions, deletions)) = counts else {
                                    warnings += 1;
                                    continue;
                                };
                                let relative = path
                                    .strip_prefix(&format!("{cwd}/"))
                                    .unwrap_or(path)
                                    .to_string();
                                if let Some(existing) =
                                    pending_files.iter_mut().find(|file| file.path == relative)
                                {
                                    existing.additions += additions;
                                    existing.deletions += deletions;
                                } else {
                                    pending_files.push(ChatFileChange {
                                        additions,
                                        deletions,
                                        path: relative,
                                    });
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }
            continue;
        }
        if record_type != "response_item" {
            continue;
        }
        let Some(payload) = payload else {
            warnings += 1;
            continue;
        };
        match text(payload.get("type")) {
            "message" => {
                let role = text(payload.get("role"));
                if role == "assistant" || (role == "user" && !saw_event_user) {
                    let (parts, has_image) = parse_message_content(payload, &mut warnings);
                    append_message(&mut rows, role, parts, Vec::new(), has_image, timestamp_ms);
                }
            }
            "function_call" | "custom_tool_call" | "local_shell_call" => {
                let payload_type = text(payload.get("type"));
                let preview_key = if payload_type == "custom_tool_call" {
                    "input"
                } else {
                    "arguments"
                };
                append_tool(
                    &mut rows,
                    &mut tool_rows,
                    text(payload.get("call_id")).into(),
                    text(payload.get("name")).into(),
                    deferred_text(payload.get(preview_key)),
                    timestamp_ms,
                );
            }
            "function_call_output" | "custom_tool_call_output" => apply_tool_result(
                &mut rows,
                &mut tool_rows,
                text(payload.get("call_id")).into(),
                deferred_text(payload.get("output")),
                false,
                timestamp_ms,
            ),
            "image_generation_call" => {
                let call_id = text(payload.get("id")).to_string();
                let index = tool_rows.get(&call_id).copied().unwrap_or_else(|| {
                    append_tool(
                        &mut rows,
                        &mut tool_rows,
                        call_id,
                        "Image generation".into(),
                        DeferredText::default(),
                        timestamp_ms,
                    )
                });
                let row = &mut rows[index];
                let has_result = !deferred_text(payload.get("result")).is_empty();
                row.row.tool_status = if text(payload.get("status")) == "failed" {
                    "failed"
                } else if has_result {
                    "completed"
                } else {
                    "unknown"
                }
                .into();
                row.row.has_image_placeholder |= has_result;
                row.ended_at_ms = row.ended_at_ms.max(timestamp_ms);
            }
            "reasoning" | "" => {}
            _ => warnings += 1,
        }
    }
    append_files(&mut rows, &mut pending_files);
    (display_rows(rows), warnings)
}

fn parse_claude_message(
    record: &ClaudeRecord,
    rows: &mut Vec<WorkingRow>,
    tool_rows: &mut HashMap<String, usize>,
) -> usize {
    let Some(message) = object(record.root.get("message")) else {
        return 1;
    };
    let Some(content) = message.get("content") else {
        return 1;
    };
    if content.is_string() {
        append_message(
            rows,
            &record.record_type,
            vec![deferred_text(Some(content))],
            Vec::new(),
            false,
            record.timestamp_ms,
        );
        return 0;
    }
    let Some(content) = content.as_array() else {
        return 1;
    };
    let mut parts = Vec::new();
    let mut has_image = false;
    let mut warnings = 0;
    enum Deferred {
        Call(String, String),
        Result(String, DeferredText, bool, bool),
    }
    let mut deferred = Vec::new();
    for raw_block in content {
        let Some(block) = raw_block.as_object() else {
            warnings += 1;
            continue;
        };
        match text(block.get("type")) {
            "text" => parts.push(deferred_text(block.get("text"))),
            "image" | "document" => has_image = true,
            "tool_use" => deferred.push(Deferred::Call(
                text(block.get("id")).into(),
                text(block.get("name")).into(),
            )),
            "tool_result" => {
                let mut previews = Vec::new();
                let mut result_image = false;
                match block.get("content") {
                    Some(value) if value.is_string() => previews.push(deferred_text(Some(value))),
                    Some(value) if value.as_array().is_some() => {
                        let values = value.as_array().unwrap();
                        for value in values {
                            if value.is_string() {
                                previews.push(deferred_text(Some(value)));
                            } else if let Some(value) = value.as_object() {
                                match text(value.get("type")) {
                                    "text" => previews.push(deferred_text(value.get("text"))),
                                    "image" => result_image = true,
                                    _ => warnings += 1,
                                }
                            }
                        }
                    }
                    _ => {}
                }
                deferred.push(Deferred::Result(
                    text(block.get("tool_use_id")).into(),
                    join_text(&previews),
                    block.get("is_error").and_then(Value::as_bool) == Some(true),
                    result_image,
                ));
            }
            "thinking" => {}
            _ => warnings += 1,
        }
    }
    append_message(
        rows,
        &record.record_type,
        parts,
        Vec::new(),
        has_image,
        record.timestamp_ms,
    );
    for item in deferred {
        match item {
            Deferred::Call(id, name) => {
                append_tool(
                    rows,
                    tool_rows,
                    id,
                    name,
                    DeferredText::default(),
                    record.timestamp_ms,
                );
            }
            Deferred::Result(id, preview, failed, image) => {
                apply_tool_result(
                    rows,
                    tool_rows,
                    id.clone(),
                    preview,
                    failed,
                    record.timestamp_ms,
                );
                if image && let Some(index) = tool_rows.get(&id) {
                    rows[*index].row.has_image_placeholder = true;
                }
            }
        }
    }
    warnings
}

fn parse_claude(source: &Arc<String>, lines: &[Range<usize>]) -> (Vec<ChatRow>, usize) {
    let mut records = Vec::new();
    let mut record_by_id = HashMap::new();
    let mut warnings = 0;
    let mut leaf_id = String::new();
    for line in lines {
        let Some(root_value) = Value::parse(source.clone(), line.clone()) else {
            warnings += 1;
            continue;
        };
        let Some(root) = root_value.as_object() else {
            warnings += 1;
            continue;
        };
        let record = ClaudeRecord {
            uuid: text(root.get("uuid")).into(),
            parent_uuid: text(root.get("parentUuid")).into(),
            record_type: text(root.get("type")).into(),
            sidechain: root.get("isSidechain").and_then(Value::as_bool) == Some(true),
            timestamp_ms: timestamp(root.get("timestamp")),
            root: root.clone(),
        };
        if !record.uuid.is_empty() && !record.sidechain {
            record_by_id.insert(record.uuid.clone(), record.parent_uuid.clone());
            leaf_id = record.uuid.clone();
        }
        records.push(record);
    }
    let mut main_chain = HashSet::new();
    let mut cursor = leaf_id;
    while !cursor.is_empty() && main_chain.insert(cursor.clone()) {
        let Some(parent) = record_by_id.get(&cursor) else {
            warnings += 1;
            break;
        };
        cursor = parent.clone();
    }
    let mut rows = Vec::new();
    let mut tool_rows = HashMap::new();
    for record in &records {
        if !record.sidechain
            && !record.uuid.is_empty()
            && main_chain.contains(&record.uuid)
            && matches!(record.record_type.as_str(), "user" | "assistant")
        {
            warnings += parse_claude_message(record, &mut rows, &mut tool_rows);
        }
    }
    (display_rows(rows), warnings)
}

pub fn parse_chat_text(
    provider: &str,
    source: &str,
) -> Result<(Vec<ChatRow>, usize, usize, f64, f64), String> {
    parse_source(provider, Arc::new(source.to_string()))
}

fn parse_source(
    provider: &str,
    source: Arc<String>,
) -> Result<(Vec<ChatRow>, usize, usize, f64, f64), String> {
    let scan_started = Instant::now();
    let mut offset = 0;
    let lines = source
        .split_inclusive('\n')
        .filter_map(|line| {
            let start = offset;
            offset += line.len();
            let line = line.trim_end_matches(['\r', '\n']);
            (!line.is_empty()).then_some(start..start + line.len())
        })
        .collect::<Vec<_>>();
    let scan_ms = scan_started.elapsed().as_secs_f64() * 1000.0;
    let parse_started = Instant::now();
    let (rows, warnings) = match provider {
        "codex" => parse_codex(&source, &lines),
        "claude" => parse_claude(&source, &lines),
        _ => return Err("Unsupported chat provider".into()),
    };
    let parse_ms = parse_started.elapsed().as_secs_f64() * 1000.0;
    Ok((rows, warnings, lines.len(), scan_ms, parse_ms))
}

pub fn open_chat_file(provider: &str, path: &Path) -> Result<ChatDocument, String> {
    let started = Instant::now();
    let load_started = Instant::now();
    let bytes = fs::read(path).map_err(|error| format!("Failed to read transcript: {error}"))?;
    let source_bytes = bytes.len();
    let source =
        String::from_utf8(bytes).map_err(|error| format!("Transcript is not UTF-8: {error}"))?;
    let load_ms = load_started.elapsed().as_secs_f64() * 1000.0;
    let (rows, warning_count, record_count, scan_ms, parse_ms) =
        parse_source(provider, Arc::new(source))?;
    Ok(ChatDocument {
        path: path.to_string_lossy().into_owned(),
        provider: provider.into(),
        record_count,
        rows,
        source_bytes,
        timing: NativeTiming {
            load_ms,
            native_total_ms: started.elapsed().as_secs_f64() * 1000.0,
            parse_ms,
            scan_ms,
        },
        warning_count,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::normalized_content_digest;

    fn fixture(name: &str) -> String {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../chat-history/tests/fixtures");
        fs::read_to_string(root.join(name)).unwrap()
    }

    #[test]
    fn normalizes_codex_fixture() {
        let (rows, warnings, records, _, _) =
            parse_chat_text("codex", &fixture("codex.jsonl")).unwrap();
        assert_eq!(records, 14);
        assert_eq!(warnings, 2);
        assert_eq!(
            rows.iter().map(|row| row.kind.as_str()).collect::<Vec<_>>(),
            ["user", "tool", "assistant", "files"]
        );
        assert_eq!(rows[0].markdown, "Hello ☺\nworld\n");
        assert_eq!(rows[1].tool_name, "Worked for 4s");
        assert_eq!(rows[1].tool_preview, "Read files, created an image");
        assert_eq!(normalized_content_digest(&rows), "ea203684aeae72fb");
    }

    #[test]
    fn normalizes_claude_fixture() {
        let (rows, warnings, records, _, _) =
            parse_chat_text("claude", &fixture("claude.jsonl")).unwrap();
        assert_eq!(records, 8);
        assert_eq!(warnings, 1);
        assert_eq!(
            rows.iter().map(|row| row.kind.as_str()).collect::<Vec<_>>(),
            ["user", "tool", "assistant"]
        );
        assert_eq!(rows[1].tool_name, "Worked for 3s");
        assert_eq!(rows[2].markdown, "Latest answer");
        assert_eq!(normalized_content_digest(&rows), "4cb20d4c68d78408");
    }

    #[test]
    fn supports_current_codex_response_user_messages() {
        let (rows, _, _, _, _) =
            parse_chat_text("codex", &fixture("codex-response-user.jsonl")).unwrap();
        assert_eq!(
            rows.iter().map(|row| row.kind.as_str()).collect::<Vec<_>>(),
            ["user", "assistant"]
        );
    }
}
