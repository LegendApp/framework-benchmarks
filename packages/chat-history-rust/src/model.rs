use serde::Serialize;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSummary {
    pub id: String,
    pub path: String,
    pub provider: String,
    pub title: String,
    pub updated_at: f64,
}

#[derive(Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatFileChange {
    pub additions: usize,
    pub deletions: usize,
    pub path: String,
}

#[derive(Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatRow {
    pub file_changes: Vec<ChatFileChange>,
    pub has_image_placeholder: bool,
    pub id: String,
    pub image_sources: Vec<String>,
    pub kind: String,
    pub markdown: String,
    pub tool_name: String,
    pub tool_preview: String,
    pub tool_status: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeTiming {
    pub load_ms: f64,
    pub native_total_ms: f64,
    pub parse_ms: f64,
    pub scan_ms: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatDocument {
    pub path: String,
    pub provider: String,
    pub record_count: usize,
    pub rows: Vec<ChatRow>,
    pub source_bytes: usize,
    pub timing: NativeTiming,
    pub warning_count: usize,
}

pub fn normalized_content_digest(rows: &[ChatRow]) -> String {
    fn update(hash: &mut u64, bytes: &[u8]) {
        for byte in bytes {
            *hash = (*hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3);
        }
    }
    fn field(hash: &mut u64, value: &str) {
        update(hash, value.len().to_string().as_bytes());
        update(hash, b":");
        update(hash, value.as_bytes());
        update(hash, b";");
    }
    let mut hash = 0xcbf29ce484222325;
    field(&mut hash, &rows.len().to_string());
    for row in rows {
        field(&mut hash, &row.kind);
        field(&mut hash, &row.markdown);
        field(&mut hash, &row.tool_name);
        field(&mut hash, &row.tool_preview);
        field(&mut hash, &row.tool_status);
        field(&mut hash, if row.has_image_placeholder { "1" } else { "0" });
        field(&mut hash, &row.image_sources.len().to_string());
        for source in &row.image_sources {
            field(&mut hash, source);
        }
        field(&mut hash, &row.file_changes.len().to_string());
        for change in &row.file_changes {
            field(&mut hash, &change.path);
            field(&mut hash, &change.additions.to_string());
            field(&mut hash, &change.deletions.to_string());
        }
    }
    format!("{hash:016x}")
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogResult {
    pub native_total_ms: f64,
    pub summaries: Vec<ChatSummary>,
}
