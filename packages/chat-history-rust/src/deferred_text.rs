use serde::{Serialize, Serializer};
use std::{
    fmt,
    ops::Deref,
    sync::{Arc, OnceLock},
};

#[derive(Clone)]
pub struct DeferredText(Arc<Inner>);
struct Inner {
    value: OnceLock<String>,
    decode: Box<dyn Fn() -> String + Send + Sync>,
    nonempty: bool,
}
impl DeferredText {
    pub fn new(nonempty: bool, decode: impl Fn() -> String + Send + Sync + 'static) -> Self {
        Self(Arc::new(Inner {
            value: OnceLock::new(),
            decode: Box::new(decode),
            nonempty,
        }))
    }
    pub fn decode_uncached(&self) -> String {
        (self.0.decode)()
    }
    pub fn is_empty(&self) -> bool {
        !self.0.nonempty
    }
}
impl Default for DeferredText {
    fn default() -> Self {
        String::new().into()
    }
}
impl From<String> for DeferredText {
    fn from(value: String) -> Self {
        Self::new(!value.is_empty(), move || value.clone())
    }
}
impl From<&str> for DeferredText {
    fn from(value: &str) -> Self {
        value.to_owned().into()
    }
}
impl Deref for DeferredText {
    type Target = str;
    fn deref(&self) -> &str {
        self.0.value.get_or_init(|| (self.0.decode)())
    }
}
impl fmt::Debug for DeferredText {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.deref().fmt(f)
    }
}
impl fmt::Display for DeferredText {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.deref().fmt(f)
    }
}
impl PartialEq<&str> for DeferredText {
    fn eq(&self, other: &&str) -> bool {
        self.deref() == *other
    }
}
impl Serialize for DeferredText {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    #[test]
    fn digest_decoding_does_not_fill_the_viewport_cache() {
        let count = Arc::new(AtomicUsize::new(0));
        let observed = count.clone();
        let text = DeferredText::new(true, move || {
            observed.fetch_add(1, Ordering::Relaxed);
            "hello".into()
        });
        assert!(!text.is_empty());
        assert_eq!(count.load(Ordering::Relaxed), 0);
        assert_eq!(text.decode_uncached(), "hello");
        assert!(text.0.value.get().is_none());
        assert_eq!(&*text, "hello");
        assert_eq!(&*text, "hello");
        assert_eq!(count.load(Ordering::Relaxed), 2);
    }
}
