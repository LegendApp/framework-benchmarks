use serde_json::value::RawValue;
use std::{
    ops::Range,
    sync::{Arc, OnceLock},
};

pub type Map<K, V> = indexmap::IndexMap<K, V>;
#[derive(Clone)]
pub struct Value(Arc<Node>);
struct Node {
    source: Arc<String>,
    range: Range<usize>,
    object: OnceLock<Map<String, Value>>,
    array: OnceLock<Vec<Value>>,
    text: OnceLock<String>,
}
impl Value {
    pub fn parse(source: Arc<String>, range: Range<usize>) -> Option<Self> {
        let raw: &RawValue = serde_json::from_str(&source[range.clone()]).ok()?;
        let start = raw.get().as_ptr() as usize - source.as_ptr() as usize;
        let end = start + raw.get().len();
        Some(Self::new(source, start..end))
    }
    fn new(source: Arc<String>, range: Range<usize>) -> Self {
        Self(Arc::new(Node {
            source,
            range,
            object: OnceLock::new(),
            array: OnceLock::new(),
            text: OnceLock::new(),
        }))
    }
    fn raw(&self) -> &str {
        &self.0.source[self.0.range.clone()]
    }
    fn child(&self, raw: &RawValue) -> Self {
        let start = raw.get().as_ptr() as usize - self.0.source.as_ptr() as usize;
        Self::new(self.0.source.clone(), start..start + raw.get().len())
    }
    pub fn is_string(&self) -> bool {
        self.raw().starts_with('"')
    }
    pub fn text_nonempty(&self) -> bool {
        self.is_string() && self.raw().len() > 2
    }
    pub fn decode_string(&self) -> String {
        serde_json::from_str(self.raw()).unwrap_or_default()
    }
    pub fn as_str(&self) -> Option<&str> {
        self.is_string().then(|| {
            self.0
                .text
                .get_or_init(|| serde_json::from_str(self.raw()).expect("validated JSON string"))
                .as_str()
        })
    }
    pub fn as_bool(&self) -> Option<bool> {
        match self.raw() {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        }
    }
    pub fn as_object(&self) -> Option<&Map<String, Value>> {
        self.raw().starts_with('{').then(|| {
            self.0.object.get_or_init(|| {
                let fields: Map<String, &RawValue> =
                    serde_json::from_str(self.raw()).expect("validated JSON object");
                fields
                    .into_iter()
                    .map(|(key, value)| (key, self.child(value)))
                    .collect()
            })
        })
    }
    pub fn as_array(&self) -> Option<&Vec<Value>> {
        self.raw().starts_with('[').then(|| {
            self.0.array.get_or_init(|| {
                let values: Vec<&RawValue> =
                    serde_json::from_str(self.raw()).expect("validated JSON array");
                values.into_iter().map(|value| self.child(value)).collect()
            })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_ignored_values_and_preserves_source_field_order() {
        for source in [r#"{"skip":[1,]}"#, r#"{"skip":"\q"}"#, r#"{"skip":01}"#] {
            assert!(Value::parse(Arc::new(source.to_string()), 0..source.len()).is_none());
        }
        let source = r#"{"z":"a\nb","a":[true,{"unused":"\u263a"}]}"#;
        let value = Value::parse(Arc::new(source.to_string()), 0..source.len()).unwrap();
        let fields = value.as_object().unwrap();
        assert_eq!(
            fields.keys().map(String::as_str).collect::<Vec<_>>(),
            ["z", "a"]
        );
        assert_eq!(fields["z"].decode_string(), "a\nb");
    }
}
