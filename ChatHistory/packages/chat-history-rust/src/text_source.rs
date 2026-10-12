use std::{fs::File, ops::Deref, path::Path};

pub(crate) enum TextSource {
    Owned(String),
    Mapped(memmap2::Mmap),
}
impl TextSource {
    pub fn open(path: &Path) -> Result<Self, String> {
        let file = File::open(path).map_err(|e| format!("Failed to open transcript: {e}"))?;
        if file.metadata().map_err(|e| e.to_string())?.len() == 0 {
            return Ok(Self::Owned(String::new()));
        }
        // As with the native apps' mappings, the opened transcript must not be
        // modified or truncated during its document lifetime. Benchmark inputs
        // are immutable; mappings are released when the last row drops its Arc.
        let bytes = unsafe { memmap2::MmapOptions::new().map_copy_read_only(&file) }
            .map_err(|e| format!("Failed to map transcript: {e}"))?;
        std::str::from_utf8(&bytes).map_err(|e| format!("Transcript is not UTF-8: {e}"))?;
        Ok(Self::Mapped(bytes))
    }
}
impl Deref for TextSource {
    type Target = str;
    fn deref(&self) -> &str {
        match self {
            Self::Owned(text) => text,
            // UTF-8 was validated when opening the immutable mapping.
            Self::Mapped(bytes) => unsafe { std::str::from_utf8_unchecked(bytes) },
        }
    }
}
