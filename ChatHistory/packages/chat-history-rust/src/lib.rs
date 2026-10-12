mod deferred_text;
mod json_range;
pub use deferred_text::DeferredText;
mod catalog;
mod model;
mod parser;

pub use catalog::{get_recent_chat_catalog, user_home};
pub use model::{
    CatalogResult, ChatDocument, ChatFileChange, ChatRow, ChatSummary, NativeTiming,
    normalized_content_digest,
};
pub use parser::{open_chat_file, parse_chat_text};

pub mod document_registry;
