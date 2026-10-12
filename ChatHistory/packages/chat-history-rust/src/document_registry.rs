use crate::{ChatDocument, ChatRow, normalized_content_digest};
use serde::Serialize;
use std::sync::Arc;

#[derive(Default)]
pub struct DocumentRegistry {
    generation: u64,
    active: Option<(String, Arc<ChatDocument>)>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentDescriptor<'a> {
    #[serde(flatten)]
    document: DescriptorMetadata<'a>,
    document_id: String,
    rows: Vec<RowDescriptor<'a>>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DescriptorMetadata<'a> {
    path: &'a str,
    provider: &'a str,
    record_count: usize,
    source_bytes: usize,
    timing: &'a crate::NativeTiming,
    warning_count: usize,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RowDescriptor<'a> {
    id: &'a str,
    kind: &'a str,
    file_changes: &'a [crate::ChatFileChange],
    image_sources: &'a [String],
    has_image_placeholder: bool,
    tool_name: &'a str,
    tool_status: &'a str,
    markdown: &'static str,
    tool_preview: &'static str,
    deferred: bool,
}
impl DocumentRegistry {
    pub fn begin_open(&mut self) -> u64 {
        self.generation += 1;
        self.active = None;
        self.generation
    }
    pub fn finish_open(
        &mut self,
        generation: u64,
        document: ChatDocument,
    ) -> Result<serde_json::Value, String> {
        if self.generation != generation {
            return Err("Document open was superseded".into());
        }
        let id = generation.to_string();
        let descriptor = DocumentDescriptor {
            document: DescriptorMetadata {
                path: &document.path,
                provider: &document.provider,
                record_count: document.record_count,
                source_bytes: document.source_bytes,
                timing: &document.timing,
                warning_count: document.warning_count,
            },
            document_id: id.clone(),
            rows: document
                .rows
                .iter()
                .map(|row| RowDescriptor {
                    id: &row.id,
                    kind: &row.kind,
                    file_changes: &row.file_changes,
                    image_sources: &row.image_sources,
                    has_image_placeholder: row.has_image_placeholder,
                    tool_name: &row.tool_name,
                    tool_status: &row.tool_status,
                    markdown: "",
                    tool_preview: "",
                    deferred: true,
                })
                .collect(),
        };
        let result = serde_json::to_value(descriptor).map_err(|error| error.to_string())?;
        self.active = Some((id, Arc::new(document)));
        Ok(result)
    }
    pub fn document(&self, id: &str) -> Result<Arc<ChatDocument>, String> {
        self.active
            .as_ref()
            .filter(|(active, _)| active == id)
            .map(|(_, document)| document.clone())
            .ok_or_else(|| "Document is no longer open".into())
    }
}
pub fn materialize_rows(
    document: &ChatDocument,
    indices: &[usize],
) -> Result<Vec<ChatRow>, String> {
    if indices.len() > 256 || indices.iter().any(|index| *index >= document.rows.len()) {
        return Err("Invalid row request".into());
    }
    Ok(indices
        .iter()
        .map(|index| document.rows[*index].clone())
        .collect())
}
pub fn content_digest(document: &ChatDocument) -> String {
    normalized_content_digest(&document.rows)
}
