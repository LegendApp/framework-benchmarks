use std::ops::Range;

use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BlockKind {
    Body,
    Code,
    Heading(u8),
    Quote,
    Table,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InlineKind {
    Code,
    Emphasis,
    Link,
    Strike,
    Strong,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InlineRange {
    pub href: Option<String>,
    pub kind: InlineKind,
    pub range: Range<usize>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MarkdownImage {
    pub alt: String,
    pub source: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MarkdownBlock {
    pub kind: BlockKind,
    pub text: String,
    pub highlights: Vec<InlineRange>,
    pub images: Vec<MarkdownImage>,
}

#[derive(Clone)]
struct ActiveInline {
    href: Option<String>,
    kind: InlineKind,
    start: usize,
}

#[derive(Clone)]
struct ActiveImage {
    alt_start: usize,
    source: String,
}

struct Builder {
    active: Vec<ActiveInline>,
    active_image: Option<ActiveImage>,
    highlights: Vec<InlineRange>,
    images: Vec<MarkdownImage>,
    kind: BlockKind,
    output: Vec<MarkdownBlock>,
    text: String,
}

impl Builder {
    fn new() -> Self {
        Self {
            active: Vec::new(),
            active_image: None,
            highlights: Vec::new(),
            images: Vec::new(),
            kind: BlockKind::Body,
            output: Vec::new(),
            text: String::new(),
        }
    }

    fn push_inline(&mut self, kind: InlineKind, href: Option<String>) {
        self.active.push(ActiveInline {
            href,
            kind,
            start: self.text.len(),
        });
    }

    fn pop_inline(&mut self, kind: InlineKind) {
        if let Some(index) = self.active.iter().rposition(|item| item.kind == kind) {
            let active = self.active.remove(index);
            if active.start < self.text.len() {
                self.highlights.push(InlineRange {
                    href: active.href,
                    kind,
                    range: active.start..self.text.len(),
                });
            }
        }
    }

    fn flush(&mut self) {
        let trimmed_len = self.text.trim_end().len();
        if trimmed_len == 0 && self.images.is_empty() {
            self.clear_block();
            return;
        }
        self.text.truncate(trimmed_len);
        self.highlights.retain_mut(|highlight| {
            highlight.range.end = highlight.range.end.min(trimmed_len);
            highlight.range.start < highlight.range.end
        });
        self.highlights
            .sort_by_key(|highlight| (highlight.range.start, highlight.range.end));
        self.output.push(MarkdownBlock {
            kind: self.kind,
            text: std::mem::take(&mut self.text),
            highlights: std::mem::take(&mut self.highlights),
            images: std::mem::take(&mut self.images),
        });
        self.active.clear();
        self.active_image = None;
    }

    fn clear_block(&mut self) {
        self.text.clear();
        self.highlights.clear();
        self.images.clear();
        self.active.clear();
        self.active_image = None;
    }
}

pub fn blocks(source: &str) -> Vec<MarkdownBlock> {
    let parser = Parser::new_ext(source, Options::all());
    let mut builder = Builder::new();
    let mut lists: Vec<(Option<u64>, u64)> = Vec::new();
    let mut table_cell = 0usize;

    for event in parser {
        match event {
            Event::Start(Tag::Heading { level, .. }) => {
                builder.flush();
                builder.kind = BlockKind::Heading(match level {
                    HeadingLevel::H1 => 1,
                    HeadingLevel::H2 => 2,
                    HeadingLevel::H3 => 3,
                    _ => 4,
                });
            }
            Event::End(TagEnd::Heading(_)) => {
                builder.flush();
                builder.kind = BlockKind::Body;
            }
            Event::Start(Tag::CodeBlock(language)) => {
                builder.flush();
                builder.kind = BlockKind::Code;
                if let CodeBlockKind::Fenced(language) = language
                    && !language.is_empty()
                {
                    builder.text.push_str(&language);
                    builder.text.push('\n');
                }
            }
            Event::End(TagEnd::CodeBlock) => {
                builder.flush();
                builder.kind = BlockKind::Body;
            }
            Event::Start(Tag::BlockQuote(_)) => {
                builder.flush();
                builder.kind = BlockKind::Quote;
            }
            Event::End(TagEnd::BlockQuote(_)) => {
                builder.flush();
                builder.kind = BlockKind::Body;
            }
            Event::Start(Tag::Table(_)) => {
                builder.flush();
                builder.kind = BlockKind::Table;
            }
            Event::End(TagEnd::Table) => {
                builder.flush();
                builder.kind = BlockKind::Body;
            }
            Event::Start(Tag::TableRow) => table_cell = 0,
            Event::End(TagEnd::TableRow) => builder.text.push('\n'),
            Event::Start(Tag::TableCell) => {
                if table_cell > 0 {
                    builder.text.push_str("  │  ");
                }
                table_cell += 1;
            }
            Event::Start(Tag::List(start)) => lists.push((start, start.unwrap_or(1))),
            Event::End(TagEnd::List(_)) => {
                lists.pop();
                if lists.is_empty() {
                    builder.flush();
                }
            }
            Event::Start(Tag::Item) => {
                if !builder.text.is_empty() && !builder.text.ends_with('\n') {
                    builder.text.push('\n');
                }
                builder
                    .text
                    .push_str(&"  ".repeat(lists.len().saturating_sub(1)));
                if let Some((start, next)) = lists.last_mut() {
                    if start.is_some() {
                        builder.text.push_str(&format!("{next}. "));
                        *next += 1;
                    } else {
                        builder.text.push_str("• ");
                    }
                }
            }
            Event::Start(Tag::Strong) => builder.push_inline(InlineKind::Strong, None),
            Event::End(TagEnd::Strong) => builder.pop_inline(InlineKind::Strong),
            Event::Start(Tag::Emphasis) => builder.push_inline(InlineKind::Emphasis, None),
            Event::End(TagEnd::Emphasis) => builder.pop_inline(InlineKind::Emphasis),
            Event::Start(Tag::Strikethrough) => builder.push_inline(InlineKind::Strike, None),
            Event::End(TagEnd::Strikethrough) => builder.pop_inline(InlineKind::Strike),
            Event::Start(Tag::Link { dest_url, .. }) => {
                builder.push_inline(InlineKind::Link, Some(dest_url.into_string()));
            }
            Event::End(TagEnd::Link) => builder.pop_inline(InlineKind::Link),
            Event::Start(Tag::Image { dest_url, .. }) => {
                builder.active_image = Some(ActiveImage {
                    alt_start: builder.text.len(),
                    source: dest_url.into_string(),
                });
            }
            Event::End(TagEnd::Image) => {
                if let Some(image) = builder.active_image.take() {
                    builder.images.push(MarkdownImage {
                        alt: builder.text[image.alt_start..].to_string(),
                        source: image.source,
                    });
                }
            }
            Event::Text(value)
            | Event::Html(value)
            | Event::InlineHtml(value)
            | Event::InlineMath(value)
            | Event::DisplayMath(value) => builder.text.push_str(&value),
            Event::Code(value) => {
                let start = builder.text.len();
                builder.text.push_str(&value);
                builder.highlights.push(InlineRange {
                    href: None,
                    kind: InlineKind::Code,
                    range: start..builder.text.len(),
                });
            }
            Event::TaskListMarker(checked) => {
                builder.text.push_str(if checked { "☑ " } else { "☐ " });
            }
            Event::FootnoteReference(value) => {
                builder.text.push('[');
                builder.text.push_str(&value);
                builder.text.push(']');
            }
            Event::SoftBreak => builder.text.push('\n'),
            Event::HardBreak => builder.text.push_str("\n\n"),
            Event::Rule => {
                builder.flush();
                builder.text.push_str("────────────────────────");
                builder.flush();
            }
            Event::End(TagEnd::Paragraph)
                if lists.is_empty() && builder.kind != BlockKind::Table =>
            {
                builder.flush();
            }
            _ => {}
        }
    }
    builder.flush();
    builder.output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_rich_inline_ranges_and_images() {
        let parsed =
            blocks("**bold _italic_** [link](https://example.com) `code` ![alt](image.png)");
        assert_eq!(parsed.len(), 1);
        assert!(
            parsed[0]
                .highlights
                .iter()
                .any(|range| range.kind == InlineKind::Strong)
        );
        assert!(
            parsed[0]
                .highlights
                .iter()
                .any(|range| range.kind == InlineKind::Emphasis)
        );
        assert!(
            parsed[0]
                .highlights
                .iter()
                .any(|range| range.kind == InlineKind::Link)
        );
        assert!(
            parsed[0]
                .highlights
                .iter()
                .any(|range| range.kind == InlineKind::Code)
        );
        assert_eq!(parsed[0].images[0].source, "image.png");
        assert_eq!(parsed[0].images[0].alt, "alt");
    }

    #[test]
    fn preserves_tables_tasks_and_ordered_lists() {
        let parsed = blocks("| A | B |\n| - | - |\n| 1 | 2 |\n\n1. first\n2. second\n\n- [x] done");
        assert!(
            parsed
                .iter()
                .any(|block| block.kind == BlockKind::Table && block.text.contains("A  │  B"))
        );
        let text = parsed
            .iter()
            .map(|block| block.text.as_str())
            .collect::<Vec<_>>()
            .join("\n");
        assert!(text.contains("1. first"));
        assert!(text.contains("☑ done"));
    }
}
