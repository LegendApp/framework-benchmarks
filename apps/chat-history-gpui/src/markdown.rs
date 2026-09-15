use std::ops::Range;

use pulldown_cmark::{Alignment, CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BlockKind {
    Body,
    Code,
    Heading(u8),
    Table,
    Rule,
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

#[derive(Clone, Debug, PartialEq)]
pub struct MarkdownBlock {
    pub kind: BlockKind,
    pub text: String,
    pub highlights: Vec<InlineRange>,
    pub images: Vec<MarkdownImage>,
    pub language: String,
    pub syntax: Vec<crate::code_syntax::CodeToken>,
    pub quote_depth: usize,
    pub list_depth: usize,
    pub marker: Option<String>,
    pub cells: Vec<Vec<MarkdownBlock>>,
    pub alignments: Vec<Alignment>,
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
    language: String,
    quote_depth: usize,
    list_depth: usize,
    marker: Option<String>,
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
            language: String::new(),
            quote_depth: 0,
            list_depth: 0,
            marker: None,
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
        // RN removes terminal newlines from code but preserves spaces and tabs.
        let trimmed_len = if self.kind == BlockKind::Code {
            self.text.trim_end_matches('\n').len()
        } else {
            self.text.trim_end().len()
        };
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
        let syntax = if self.kind == BlockKind::Code {
            crate::code_syntax::highlight(&self.text, &self.language)
        } else {
            vec![]
        };
        self.output.push(MarkdownBlock {
            kind: self.kind,
            text: std::mem::take(&mut self.text),
            highlights: std::mem::take(&mut self.highlights),
            images: std::mem::take(&mut self.images),
            syntax,
            language: std::mem::take(&mut self.language),
            quote_depth: self.quote_depth,
            list_depth: self.list_depth,
            marker: self.marker.take(),
            cells: Vec::new(),
            alignments: Vec::new(),
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
    let parser = Parser::new_ext(
        source,
        Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH | Options::ENABLE_TASKLISTS,
    );
    let mut builder = Builder::new();
    let mut lists: Vec<(Option<u64>, u64)> = Vec::new();
    let mut table_rows: Vec<Vec<MarkdownBlock>> = Vec::new();
    let mut table_alignment = Vec::new();
    let mut in_table = false;

    for event in parser {
        match event {
            Event::Start(Tag::Heading { level, .. }) => {
                builder.flush();
                builder.kind = BlockKind::Heading(match level {
                    HeadingLevel::H1 => 1,
                    HeadingLevel::H2 => 2,
                    HeadingLevel::H3 => 3,
                    HeadingLevel::H4 => 4,
                    HeadingLevel::H5 => 5,
                    HeadingLevel::H6 => 6,
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
                    builder.language = language.split_whitespace().next().unwrap_or_default().to_owned();
                }
            }
            Event::End(TagEnd::CodeBlock) => {
                builder.flush();
                builder.kind = BlockKind::Body;
            }
            Event::Start(Tag::BlockQuote(_)) => {
                builder.flush();
                builder.quote_depth += 1;
            }
            Event::End(TagEnd::BlockQuote(_)) => {
                builder.flush();
                builder.quote_depth = builder.quote_depth.saturating_sub(1);
            }
            Event::Start(Tag::Table(alignment)) => {
                builder.flush();
                in_table = true;
                table_alignment = alignment;
                table_rows.clear();
            }
            Event::Start(Tag::TableHead) | Event::Start(Tag::TableRow) => {
                table_rows.push(Vec::new())
            }
            Event::End(TagEnd::TableCell) => {
                // Preserve each cell's inline spans independently, including empty cells.
                let before = builder.output.len();
                builder.flush();
                let cell = if builder.output.len() > before {
                    builder.output.pop().unwrap()
                } else {
                    MarkdownBlock {
                        kind: BlockKind::Body,
                        text: String::new(),
                        highlights: vec![],
                        images: vec![],
                        language: String::new(),
                        syntax: vec![],
                        quote_depth: 0,
                        list_depth: 0,
                        marker: None,
                        cells: vec![],
                        alignments: vec![],
                    }
                };
                table_rows.last_mut().unwrap().push(cell);
            }
            Event::End(TagEnd::Table) => {
                in_table = false;
                builder.output.push(MarkdownBlock {
                    kind: BlockKind::Table,
                    text: String::new(),
                    highlights: vec![],
                    images: vec![],
                    language: String::new(),
                    syntax: vec![],
                    quote_depth: builder.quote_depth,
                    list_depth: builder.list_depth,
                    marker: builder.marker.take(),
                    cells: std::mem::take(&mut table_rows),
                    alignments: std::mem::take(&mut table_alignment),
                });
            }
            Event::Start(Tag::List(start)) => {
                builder.flush();
                lists.push((start, start.unwrap_or(1)));
                builder.list_depth = lists.len();
            }
            Event::End(TagEnd::List(_)) => {
                builder.flush();
                lists.pop();
                builder.list_depth = lists.len();
                if lists.is_empty() {
                    builder.flush();
                }
            }
            Event::Start(Tag::Item) => {
                builder.flush();
                if let Some((start, next)) = lists.last_mut() {
                    builder.marker = Some(if start.is_some() {
                        let marker = format!("{next}.");
                        *next += 1;
                        marker
                    } else {
                        "•".into()
                    });
                }
            }
            Event::End(TagEnd::Item) => builder.flush(),
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
                    builder.text.truncate(image.alt_start);
                    builder.highlights.retain_mut(|highlight| {
                        highlight.range.end = highlight.range.end.min(image.alt_start);
                        highlight.range.start < highlight.range.end
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
                builder.marker = Some(if checked { "☑" } else { "☐" }.into());
            }
            Event::FootnoteReference(value) => {
                builder.text.push('[');
                builder.text.push_str(&value);
                builder.text.push(']');
            }
            Event::SoftBreak => builder.text.push(' '),
            Event::HardBreak => builder.text.push('\n'),
            Event::Rule => {
                builder.flush();
                builder.output.push(MarkdownBlock {
                    kind: BlockKind::Rule,
                    text: String::new(),
                    highlights: vec![],
                    images: vec![],
                    language: String::new(),
                    syntax: vec![],
                    quote_depth: builder.quote_depth,
                    list_depth: builder.list_depth,
                    marker: builder.marker.take(),
                    cells: vec![],
                    alignments: vec![],
                });
            }
            Event::End(TagEnd::Paragraph) if !in_table => {
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
    fn code_panes_preserve_spaces_and_use_only_the_fence_language() {
        let parsed = blocks("```rust title=example\nlet x = 1;  \n\n``` ");
        assert_eq!(parsed[0].language, "rust");
        assert_eq!(parsed[0].text, "let x = 1;  ");
        let whitespace = blocks("```text\n  \t\n```");
        assert_eq!(whitespace[0].text, "  \t");
    }

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
    fn retains_nested_layout_and_code_header_metadata() {
        let parsed = blocks(
            "> outer\n>\n> > nested **bold**\n\n- parent\n  - child\n\n```rust\nlet x = 1;\n```\n\n---",
        );
        assert!(
            parsed
                .iter()
                .any(|block| block.quote_depth == 2 && block.text == "nested bold")
        );
        assert!(parsed.iter().any(|block| block.list_depth == 2
            && block.marker.as_deref() == Some("•")
            && block.text == "child"));
        assert!(parsed.iter().any(|block| block.kind == BlockKind::Code
            && block.language == "rust"
            && block.text == "let x = 1;"));
        assert!(
            parsed
                .iter()
                .any(|block| block.kind == BlockKind::Rule && block.text.is_empty())
        );
    }

    #[test]
    fn preserves_tables_tasks_and_ordered_lists() {
        let parsed = blocks("| A | B |\n| - | - |\n| 1 | 2 |\n\n1. first\n2. second\n\n- [x] done");
        assert!(parsed.iter().any(|block| block.kind == BlockKind::Table
            && block.cells[0][0].text == "A"
            && block.cells[0][1].text == "B"));
        let text = parsed
            .iter()
            .map(|block| block.text.as_str())
            .collect::<Vec<_>>()
            .join("\n");
        assert!(text.contains("first"));
        assert!(
            parsed
                .iter()
                .any(|block| block.marker.as_deref() == Some("1."))
        );
        assert!(
            parsed
                .iter()
                .any(|block| block.marker.as_deref() == Some("☑") && block.text == "done")
        );
    }
}
