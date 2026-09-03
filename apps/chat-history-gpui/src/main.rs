mod benchmark;
mod markdown;
mod settings;

use std::{
    collections::HashSet,
    path::PathBuf,
    sync::{Arc, OnceLock},
    time::{Duration, Instant},
};

use benchmark::{Benchmark, emit_window_shown};
use chat_history_rust::{
    ChatDocument, ChatRow, ChatSummary, get_recent_chat_catalog, open_chat_file, user_home,
};
use chrono::{Local, TimeZone};
use gpui::{
    AnyElement, AnyWindowHandle, App, Application, Bounds, Context, Div, FontStyle, FontWeight,
    HighlightStyle, InteractiveText, ListAlignment, ListState, Render, StrikethroughStyle,
    StyledText, Task, TitlebarOptions, UnderlineStyle, Window, WindowAppearance, WindowBounds,
    WindowOptions, div, img, list, prelude::*, px, rgb, rgba, size,
};
use markdown::{BlockKind, InlineKind, MarkdownBlock, blocks};
use settings::Settings;

#[derive(Clone, Copy)]
struct Palette {
    accent: gpui::Rgba,
    background: gpui::Rgba,
    border: gpui::Rgba,
    code: gpui::Rgba,
    muted: gpui::Rgba,
    sidebar: gpui::Rgba,
    text: gpui::Rgba,
    user: gpui::Rgba,
}

impl Palette {
    fn new(dark: bool) -> Self {
        if dark {
            Self {
                accent: rgb(0x4f8cff),
                background: rgb(0x191a1b),
                border: rgb(0x36383a),
                code: rgb(0x25272a),
                muted: rgb(0x9a9da2),
                sidebar: rgb(0x202224),
                text: rgb(0xf1f2f3),
                user: rgb(0x2b2e31),
            }
        } else {
            Self {
                accent: rgb(0x1769e0),
                background: rgb(0xffffff),
                border: rgb(0xdfe2e6),
                code: rgb(0xf2f3f5),
                muted: rgb(0x6b7179),
                sidebar: rgb(0xf5f6f8),
                text: rgb(0x202124),
                user: rgb(0xf0f1f3),
            }
        }
    }
}

struct ChatHistory {
    benchmark: Option<Benchmark>,
    catalog_loaded: bool,
    catalog_ms: f64,
    document: Option<Arc<ChatDocument>>,
    error: Option<String>,
    expanded_files: HashSet<String>,
    expanded_tools: HashSet<String>,
    generation: usize,
    list_state: ListState,
    loading: bool,
    loading_task: Option<Task<()>>,
    markdown: Arc<Vec<OnceLock<Vec<MarkdownBlock>>>>,
    selected_id: Option<String>,
    settings: Settings,
    settings_open: bool,
    summaries: Arc<Vec<ChatSummary>>,
    window: AnyWindowHandle,
}

struct PendingReady {
    generation: usize,
    phase: &'static str,
    started: Instant,
}

#[derive(Clone, Copy)]
struct RowRenderState {
    files_expanded: bool,
    index: usize,
    load_images: bool,
    palette: Palette,
    tool_expanded: bool,
}

impl ChatHistory {
    fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let settings = Settings::load();
        let benchmark = Benchmark::load().unwrap_or_else(|error| {
            eprintln!("{error}");
            None
        });
        let summaries = benchmark
            .as_ref()
            .map(|value| value.fixtures.clone())
            .unwrap_or_default();
        let catalog_loaded = benchmark.is_some();
        let mut view = Self {
            benchmark,
            catalog_loaded,
            catalog_ms: 0.0,
            document: None,
            error: None,
            expanded_files: HashSet::new(),
            expanded_tools: HashSet::new(),
            generation: 0,
            list_state: ListState::new(0, ListAlignment::Bottom, px(600.0)),
            loading: true,
            loading_task: None,
            markdown: Arc::new(Vec::new()),
            selected_id: None,
            settings,
            settings_open: false,
            summaries: Arc::new(summaries),
            window: window.window_handle(),
        };
        if let Some(benchmark) = &view.benchmark {
            view.settings.load_images = benchmark.load_images;
            if let Some(initial) = benchmark.fixtures.first().cloned() {
                view.select(initial, Some("initial"), cx);
            }
        } else {
            view.refresh_catalog(cx);
        }
        view
    }

    fn refresh_catalog(&mut self, cx: &mut Context<Self>) {
        self.loading = true;
        self.error = None;
        let limit = self.settings.recent_chat_limit;
        let selected_id = self
            .settings
            .restore_selection
            .then(|| self.settings.selected_id.clone())
            .flatten();
        let task = cx.background_spawn(async move {
            let home = user_home()?;
            Ok::<_, String>(get_recent_chat_catalog(limit, &home))
        });
        self.loading_task = Some(cx.spawn(async move |this, cx| {
            let result = task.await;
            let _ = this.update(cx, |view, cx| match result {
                Ok(catalog) => {
                    view.catalog_loaded = true;
                    view.catalog_ms = catalog.native_total_ms;
                    view.summaries = Arc::new(catalog.summaries);
                    let initial = selected_id
                        .as_deref()
                        .and_then(|id| view.summaries.iter().find(|item| item.id == id))
                        .cloned()
                        .or_else(|| view.summaries.first().cloned());
                    view.loading = false;
                    if let Some(summary) = initial {
                        view.select(summary, None, cx);
                    } else {
                        view.generation += 1;
                        view.selected_id = None;
                        view.document = None;
                        view.markdown = Arc::new(Vec::new());
                        view.list_state.reset(0);
                        cx.notify();
                    }
                }
                Err(error) => {
                    view.loading = false;
                    view.error = Some(error);
                    cx.notify();
                }
            });
        }));
    }

    fn select(
        &mut self,
        summary: ChatSummary,
        phase: Option<&'static str>,
        cx: &mut Context<Self>,
    ) {
        self.generation += 1;
        let generation = self.generation;
        self.selected_id = Some(summary.id.clone());
        self.loading = true;
        self.error = None;
        self.document = None;
        self.expanded_files.clear();
        self.expanded_tools.clear();
        self.markdown = Arc::new(Vec::new());
        self.list_state.reset(0);
        if phase.is_none() && self.settings.restore_selection {
            self.settings.selected_id = Some(summary.id.clone());
            self.settings.save();
        }
        cx.notify();

        let provider = summary.provider.clone();
        let path = PathBuf::from(summary.path.clone());
        let started = Instant::now();
        let task = cx.background_spawn(async move {
            let document = open_chat_file(&provider, &path)?;
            Ok::<_, String>(document)
        });
        self.loading_task = Some(cx.spawn(async move |this, cx| {
            let result = task.await;
            let window = this
                .update(cx, |view, cx| {
                    if generation != view.generation {
                        return None;
                    }
                    match result {
                        Ok(document) => {
                            let row_count = document.rows.len();
                            view.list_state.reset(row_count);
                            view.document = Some(Arc::new(document));
                            view.markdown = Arc::new(
                                (0..row_count).map(|_| OnceLock::new()).collect(),
                            );
                            view.loading = false;
                            let pending = phase.and_then(|phase| {
                                view.benchmark.as_ref().map(|_| PendingReady {
                                    generation,
                                    phase,
                                    started,
                                })
                            });
                            cx.notify();
                            return Some((view.window, pending));
                        }
                        Err(error) => {
                            eprintln!("Chat load failed: {error}");
                            view.loading = false;
                            view.error = Some(error);
                            cx.notify();
                        }
                    }
                    Some((view.window, None))
                })
                .ok()
                .flatten();
            if let Some((window, pending)) = window {
                let _ = window.update(cx, |root, window, cx| {
                    cx.notify(root.entity_id());
                    window.refresh();
                });
                if let Some(pending) = pending {
                    cx.background_executor()
                        .timer(Duration::from_millis(50))
                        .await;
                    let _ = this.update(cx, |view, cx| view.emit_ready(pending, cx));
                }
            }
        }));
    }

    fn emit_ready(&mut self, pending: PendingReady, cx: &mut Context<Self>) {
        if pending.generation != self.generation {
            return;
        }
        let Some(benchmark) = self.benchmark.as_ref() else {
            return;
        };
        let Some(document) = self.document.as_ref() else {
            return;
        };
        let duration_ms = pending.started.elapsed().as_secs_f64() * 1000.0;
        let timing = &document.timing;
        let _ = benchmark.emit(serde_json::json!({
            "contentDigest": document.content_digest,
            "durationMs": duration_ms,
            "name": "contentReady",
            "path": document.path,
            "phase": pending.phase,
            "recordCount": document.record_count,
            "rowCount": document.rows.len(),
            "sourceBytes": document.source_bytes,
            "timing": {
                "loadMs": timing.load_ms,
                "nativeTotalMs": timing.native_total_ms,
                "parseMs": timing.parse_ms,
                "scanMs": timing.scan_ms
            }
        }));
        if pending.phase != "initial" {
            return;
        }
        let Some(summary) = benchmark.fixtures.get(1).cloned() else {
            return;
        };
        let delay_ms = benchmark.switch_delay_ms;
        let generation = pending.generation;
        self.loading_task = Some(cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(Duration::from_millis(delay_ms))
                .await;
            let _ = this.update(cx, |view, cx| {
                if generation == view.generation {
                    view.select(summary, Some("switch"), cx);
                }
            });
        }));
    }

    fn is_dark(&self, window: &Window) -> bool {
        match self.settings.appearance.as_str() {
            "dark" => true,
            "light" => false,
            _ => matches!(
                window.appearance(),
                WindowAppearance::Dark | WindowAppearance::VibrantDark
            ),
        }
    }

    fn render_sidebar(&self, palette: Palette, cx: &mut Context<Self>) -> Div {
        let selected_id = self.selected_id.clone();
        let mut entries = Vec::<AnyElement>::new();
        for (section_index, (provider, title)) in [("codex", "Codex"), ("claude", "Claude")]
            .into_iter()
            .enumerate()
        {
            if section_index > 0 {
                entries.push(div().h(px(12.0)).flex_none().into_any_element());
            }
            entries.push(
                div()
                    .h(px(40.0))
                    .flex_none()
                    .flex()
                    .items_center()
                    .px(px(16.0))
                    .text_sm()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(palette.muted)
                    .child(title)
                    .into_any_element(),
            );
            for summary in self
                .summaries
                .iter()
                .filter(|summary| summary.provider == provider)
            {
                let selected = selected_id.as_deref() == Some(&summary.id);
                let summary_for_click = summary.clone();
                entries.push(
                    div()
                        .id(gpui::SharedString::from(format!("chat-{}", summary.id)))
                        .h(px(34.0))
                        .flex_none()
                        .mx(px(8.0))
                        .px(px(8.0))
                        .rounded(px(7.0))
                        .flex()
                        .items_center()
                        .justify_between()
                        .cursor_pointer()
                        .when(selected, |item| item.bg(palette.accent))
                        .hover(|item| {
                            item.bg(if selected {
                                palette.accent
                            } else {
                                palette.background
                            })
                        })
                        .on_click(cx.listener(move |view, _, _, cx| {
                            view.select(summary_for_click.clone(), None, cx);
                        }))
                        .child(
                            div()
                                .min_w(px(0.0))
                                .overflow_hidden()
                                .text_sm()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(if selected {
                                    rgb(0xffffff)
                                } else {
                                    palette.text
                                })
                                .child(summary.title.clone()),
                        )
                        .child(
                            div()
                                .ml(px(6.0))
                                .flex_none()
                                .text_xs()
                                .text_color(if selected {
                                    rgba(0xffffffb3)
                                } else {
                                    palette.muted
                                })
                                .child(format_date(summary.updated_at)),
                        )
                        .into_any_element(),
                );
            }
        }
        div()
            .w(px(260.0))
            .h_full()
            .flex_none()
            .flex()
            .flex_col()
            .bg(palette.sidebar)
            .border_r_1()
            .border_color(palette.border)
            .child(
                div()
                    .h(px(52.0))
                    .flex_none()
                    .flex()
                    .items_center()
                    .px(px(16.0))
                    .font_weight(FontWeight::SEMIBOLD)
                    .child("Chat History"),
            )
            .child(
                div()
                    .id("sidebar-scroll")
                    .flex_1()
                    .min_h(px(0.0))
                    .overflow_y_scroll()
                    .children(entries),
            )
            .child(
                div()
                    .id("open-settings")
                    .h(px(48.0))
                    .flex_none()
                    .flex()
                    .items_center()
                    .px(px(14.0))
                    .border_t_1()
                    .border_color(palette.border)
                    .cursor_pointer()
                    .hover(|item| item.bg(palette.background))
                    .on_click(cx.listener(|view, _, _, cx| {
                        view.settings_open = true;
                        cx.notify();
                    }))
                    .child("⚙  Settings"),
            )
    }

    fn render_content(
        &self,
        palette: Palette,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Div {
        let title = self
            .summaries
            .iter()
            .find(|summary| Some(summary.id.as_str()) == self.selected_id.as_deref())
            .map(|summary| summary.title.clone())
            .unwrap_or_else(|| "Select a chat".into());
        let header = div()
            .h(px(52.0))
            .flex_none()
            .flex()
            .items_center()
            .justify_between()
            .px(px(18.0))
            .border_b_1()
            .border_color(palette.border)
            .child(div().font_weight(FontWeight::SEMIBOLD).child(title))
            .child(
                div()
                    .text_xs()
                    .text_color(palette.muted)
                    .child("GPUI · Rust · GPU-native"),
            );

        let body = if self.loading {
            div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(palette.muted)
                .child(if self.selected_id.is_some() {
                    "Loading transcript…"
                } else {
                    "Scanning recent chats…"
                })
                .into_any_element()
        } else if let Some(error) = &self.error {
            div()
                .flex_1()
                .p(px(24.0))
                .text_color(rgb(0xc9362b))
                .child(error.clone())
                .into_any_element()
        } else if let Some(document) = &self.document {
            let document = document.clone();
            let markdown = self.markdown.clone();
            let expanded_tools = self.expanded_tools.clone();
            let expanded_files = self.expanded_files.clone();
            let load_images = self.settings.load_images;
            let view = cx.entity();
            list(self.list_state.clone(), move |index, window, _cx| {
                let row = &document.rows[index];
                let markdown = markdown[index].get_or_init(|| blocks(&row.markdown));
                render_row(
                    row,
                    markdown,
                    RowRenderState {
                        files_expanded: expanded_files.contains(&row.id),
                        index,
                        load_images,
                        palette,
                        tool_expanded: expanded_tools.contains(&row.id),
                    },
                    &view,
                    window,
                )
            })
            .size_full()
            .into_any_element()
        } else {
            let message = if self.catalog_loaded && self.summaries.is_empty() {
                "No local Codex or Claude transcripts found."
            } else {
                "No transcript selected"
            };
            div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(palette.muted)
                .child(message)
                .into_any_element()
        };

        div()
            .flex_1()
            .min_w(px(0.0))
            .h_full()
            .flex()
            .flex_col()
            .bg(palette.background)
            .child(header)
            .when(self.settings.show_performance_metrics, |content| {
                content.when_some(self.document.as_ref(), |content, document| {
                    content.child(
                        div()
                            .h(px(28.0))
                            .flex_none()
                            .flex()
                            .items_center()
                            .px(px(18.0))
                            .bg(palette.code)
                            .text_xs()
                            .text_color(palette.muted)
                            .child(format!(
                                "catalog {:.1} ms  ·  load {:.1}  scan {:.1}  parse {:.1}  ·  {} rows  ·  bridge 0 ms",
                                self.catalog_ms,
                                document.timing.load_ms,
                                document.timing.scan_ms,
                                document.timing.parse_ms,
                                document.rows.len(),
                            )),
                    )
                })
            })
            .child(body)
    }

    fn render_settings(&self, palette: Palette, cx: &mut Context<Self>) -> AnyElement {
        let appearance = self.settings.appearance.clone();
        let recent = self.settings.recent_chat_limit;
        div()
            .absolute()
            .inset_0()
            .bg(rgba(0x00000066))
            .flex()
            .items_center()
            .justify_center()
            .child(
                div()
                    .w(px(460.0))
                    .p(px(20.0))
                    .rounded(px(12.0))
                    .border_1()
                    .border_color(palette.border)
                    .bg(palette.background)
                    .child(
                        div()
                            .flex()
                            .justify_between()
                            .items_center()
                            .mb(px(18.0))
                            .child(
                                div()
                                    .text_xl()
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .child("Settings"),
                            )
                            .child(
                                div()
                                    .id("close-settings")
                                    .cursor_pointer()
                                    .text_color(palette.muted)
                                    .on_click(cx.listener(|view, _, _, cx| {
                                        view.settings_open = false;
                                        view.settings.save();
                                        cx.notify();
                                    }))
                                    .child("Done"),
                            ),
                    )
                    .child(setting_button(
                        "Appearance",
                        capitalize(&appearance),
                        palette,
                        cx.listener(|view, _, _, cx| {
                            view.settings.appearance = match view.settings.appearance.as_str() {
                                "system" => "light",
                                "light" => "dark",
                                _ => "system",
                            }
                            .into();
                            view.settings.save();
                            cx.notify();
                        }),
                    ))
                    .child(setting_button(
                        "Recent chats",
                        recent.to_string(),
                        palette,
                        cx.listener(|view, _, _, cx| {
                            view.settings.recent_chat_limit = match view.settings.recent_chat_limit
                            {
                                20 => 50,
                                50 => 100,
                                _ => 20,
                            };
                            view.settings.save();
                            if view.benchmark.is_none() {
                                view.refresh_catalog(cx);
                            } else {
                                cx.notify();
                            }
                        }),
                    ))
                    .child(toggle_setting(
                        "Restore last selected chat",
                        self.settings.restore_selection,
                        palette,
                        cx.listener(|view, _, _, cx| {
                            view.settings.restore_selection = !view.settings.restore_selection;
                            if !view.settings.restore_selection {
                                view.settings.selected_id = None;
                            }
                            view.settings.save();
                            cx.notify();
                        }),
                    ))
                    .child(toggle_setting(
                        "Load attached images",
                        self.settings.load_images,
                        palette,
                        cx.listener(|view, _, _, cx| {
                            view.settings.load_images = !view.settings.load_images;
                            view.settings.save();
                            cx.notify();
                        }),
                    ))
                    .child(toggle_setting(
                        "Show performance metrics",
                        self.settings.show_performance_metrics,
                        palette,
                        cx.listener(|view, _, _, cx| {
                            view.settings.show_performance_metrics =
                                !view.settings.show_performance_metrics;
                            view.settings.save();
                            cx.notify();
                        }),
                    )),
            )
            .into_any_element()
    }
}

impl Render for ChatHistory {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let palette = Palette::new(self.is_dark(window));
        div()
            .relative()
            .size_full()
            .flex()
            .text_color(palette.text)
            .bg(palette.background)
            .child(self.render_sidebar(palette, cx))
            .child(self.render_content(palette, window, cx))
            .when(self.settings_open, |root| {
                root.child(self.render_settings(palette, cx))
            })
    }
}

fn render_row(
    row: &ChatRow,
    markdown: &[MarkdownBlock],
    state: RowRenderState,
    view: &gpui::Entity<ChatHistory>,
    window: &mut Window,
) -> AnyElement {
    let RowRenderState {
        files_expanded,
        index,
        load_images,
        palette,
        tool_expanded,
    } = state;
    match row.kind.as_str() {
        "tool" => {
            let id = row.id.clone();
            let id_for_click = id.clone();
            div()
                .mx_auto()
                .w_full()
                .max_w(px(860.0))
                .px(px(18.0))
                .py(px(5.0))
                .child(
                    div()
                        .id(gpui::SharedString::from(format!("tool-{id}")))
                        .p(px(10.0))
                        .rounded(px(8.0))
                        .border_1()
                        .border_color(palette.border)
                        .bg(palette.code)
                        .cursor_pointer()
                        .on_click(window.listener_for(view, move |state, _, _, cx| {
                            if !state.expanded_tools.remove(&id_for_click) {
                                state.expanded_tools.insert(id_for_click.clone());
                            }
                            state.list_state.splice(index..index + 1, 1);
                            cx.notify();
                        }))
                        .child(
                            div()
                                .flex()
                                .justify_between()
                                .text_sm()
                                .font_weight(FontWeight::SEMIBOLD)
                                .child(row.tool_name.clone())
                                .child(if tool_expanded { "⌃" } else { "⌄" }),
                        )
                        .when(!row.tool_preview.is_empty(), |tool| {
                            tool.child(div().mt(px(5.0)).text_sm().text_color(palette.muted).child(
                                if tool_expanded {
                                    row.tool_preview.clone()
                                } else {
                                    preview(&row.tool_preview, 180)
                                },
                            ))
                        }),
                )
                .into_any_element()
        }
        "files" => {
            let id = row.id.clone();
            let id_for_click = id.clone();
            let changes = row.file_changes.clone();
            div()
                .mx_auto()
                .w_full()
                .max_w(px(860.0))
                .px(px(18.0))
                .py(px(5.0))
                .child(
                    div()
                        .id(gpui::SharedString::from(format!("files-{id}")))
                        .p(px(10.0))
                        .rounded(px(8.0))
                        .border_1()
                        .border_color(palette.border)
                        .cursor_pointer()
                        .on_click(window.listener_for(view, move |state, _, _, cx| {
                            if !state.expanded_files.remove(&id_for_click) {
                                state.expanded_files.insert(id_for_click.clone());
                            }
                            state.list_state.splice(index..index + 1, 1);
                            cx.notify();
                        }))
                        .child(
                            div()
                                .font_weight(FontWeight::SEMIBOLD)
                                .child(format!("{} changed files", changes.len())),
                        )
                        .when(files_expanded, |card| {
                            card.children(changes.into_iter().map(|file| {
                                div()
                                    .mt(px(7.0))
                                    .flex()
                                    .justify_between()
                                    .text_sm()
                                    .child(file.path)
                                    .child(format!("+{}  −{}", file.additions, file.deletions))
                            }))
                        }),
                )
                .into_any_element()
        }
        _ => {
            let is_user = row.kind == "user";
            div()
                .mx_auto()
                .w_full()
                .max_w(px(860.0))
                .px(px(18.0))
                .py(px(9.0))
                .child(
                    div()
                        .when(is_user, |message| {
                            message.p(px(13.0)).rounded(px(12.0)).bg(palette.user)
                        })
                        .child(render_markdown(&row.id, markdown, palette, load_images))
                        .when(row.has_image_placeholder, |message| {
                            message.child(
                                div()
                                    .mt(px(8.0))
                                    .text_sm()
                                    .text_color(palette.muted)
                                    .child("Image attachment"),
                            )
                        })
                        .when(load_images, |message| {
                            message.children(row.image_sources.iter().filter_map(|source| {
                                let path = PathBuf::from(source);
                                path.exists().then(|| {
                                    img(path).mt(px(9.0)).max_h(px(360.0)).rounded(px(8.0))
                                })
                            }))
                        }),
                )
                .into_any_element()
        }
    }
}

fn render_markdown(
    row_id: &str,
    blocks: &[MarkdownBlock],
    palette: Palette,
    load_images: bool,
) -> Div {
    let row_id = row_id.to_string();
    div()
        .flex()
        .flex_col()
        .gap(px(7.0))
        .children(blocks.iter().cloned().enumerate().map(|(index, block)| {
            let text = styled_markdown_text(&block, palette, format!("markdown-{row_id}-{index}"));
            let images = block.images.clone();
            match block.kind {
                BlockKind::Heading(level) => div()
                    .text_size(px(match level {
                        1 => 24.0,
                        2 => 20.0,
                        _ => 17.0,
                    }))
                    .font_weight(FontWeight::BOLD)
                    .child(text)
                    .into_any_element(),
                BlockKind::Code => div()
                    .p(px(10.0))
                    .rounded(px(7.0))
                    .bg(palette.code)
                    .font_family("SF Mono")
                    .text_sm()
                    .child(text)
                    .into_any_element(),
                BlockKind::Quote => div()
                    .pl(px(10.0))
                    .border_l_2()
                    .border_color(palette.border)
                    .text_color(palette.muted)
                    .child(text)
                    .into_any_element(),
                BlockKind::Table => div()
                    .p(px(9.0))
                    .rounded(px(7.0))
                    .border_1()
                    .border_color(palette.border)
                    .font_family("SF Mono")
                    .text_sm()
                    .child(text)
                    .into_any_element(),
                BlockKind::Body => div()
                    .child(text)
                    .when(load_images, |body| {
                        body.children(images.into_iter().map(|image| {
                            div()
                                .mt(px(8.0))
                                .child(img(image.source).max_h(px(360.0)).rounded(px(8.0)))
                        }))
                    })
                    .into_any_element(),
            }
        }))
}

fn styled_markdown_text(block: &MarkdownBlock, palette: Palette, id: String) -> InteractiveText {
    let mut boundaries = Vec::with_capacity(block.highlights.len() * 2 + 2);
    boundaries.push(0);
    boundaries.push(block.text.len());
    for highlight in &block.highlights {
        boundaries.push(highlight.range.start);
        boundaries.push(highlight.range.end);
    }
    boundaries.sort_unstable();
    boundaries.dedup();

    let mut highlights = Vec::new();
    for pair in boundaries.windows(2) {
        let range = pair[0]..pair[1];
        if range.is_empty() {
            continue;
        }
        let mut style = HighlightStyle::default();
        for highlight in block.highlights.iter().filter(|highlight| {
            highlight.range.start <= range.start && highlight.range.end >= range.end
        }) {
            match highlight.kind {
                InlineKind::Code => {
                    style.background_color = Some(palette.code.into());
                }
                InlineKind::Emphasis => style.font_style = Some(FontStyle::Italic),
                InlineKind::Link => {
                    style.color = Some(palette.accent.into());
                    style.underline = Some(UnderlineStyle {
                        thickness: px(1.0),
                        color: Some(palette.accent.into()),
                        wavy: false,
                    });
                }
                InlineKind::Strike => {
                    style.strikethrough = Some(StrikethroughStyle {
                        thickness: px(1.0),
                        color: None,
                    });
                }
                InlineKind::Strong => style.font_weight = Some(FontWeight::BOLD),
            }
        }
        if style != HighlightStyle::default() {
            highlights.push((range, style));
        }
    }
    let text = StyledText::new(block.text.clone()).with_highlights(highlights);
    let links = block
        .highlights
        .iter()
        .filter_map(|highlight| {
            highlight
                .href
                .as_ref()
                .map(|href| (highlight.range.clone(), href.clone()))
        })
        .collect::<Vec<_>>();
    let ranges = links.iter().map(|(range, _)| range.clone()).collect();
    InteractiveText::new(gpui::SharedString::from(id), text).on_click(
        ranges,
        move |index, _window, cx| {
            if let Some((_, href)) = links.get(index) {
                cx.open_url(href);
            }
        },
    )
}

fn setting_button(
    label: &'static str,
    value: String,
    palette: Palette,
    listener: impl Fn(&gpui::ClickEvent, &mut Window, &mut App) + 'static,
) -> Div {
    div()
        .h(px(46.0))
        .flex()
        .items_center()
        .justify_between()
        .border_b_1()
        .border_color(palette.border)
        .child(label)
        .child(
            div()
                .id(label)
                .px(px(10.0))
                .py(px(5.0))
                .rounded(px(6.0))
                .bg(palette.code)
                .cursor_pointer()
                .on_click(listener)
                .child(value),
        )
}

fn toggle_setting(
    label: &'static str,
    value: bool,
    palette: Palette,
    listener: impl Fn(&gpui::ClickEvent, &mut Window, &mut App) + 'static,
) -> Div {
    setting_button(
        label,
        if value { "On" } else { "Off" }.into(),
        palette,
        listener,
    )
}

fn format_date(timestamp_ms: f64) -> String {
    Local
        .timestamp_millis_opt(timestamp_ms as i64)
        .single()
        .map(|value| value.format("%b %-d").to_string())
        .unwrap_or_default()
}

fn preview(value: &str, max: usize) -> String {
    if value.chars().count() <= max {
        return value.into();
    }
    format!("{}…", value.chars().take(max).collect::<String>())
}

fn capitalize(value: &str) -> String {
    let mut characters = value.chars();
    match characters.next() {
        Some(first) => first.to_uppercase().collect::<String>() + characters.as_str(),
        None => String::new(),
    }
}

fn main() {
    Application::new().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(1280.0), px(720.0)), cx);
        cx.open_window(
            WindowOptions {
                focus: true,
                titlebar: Some(TitlebarOptions {
                    title: Some("Legend Chat History — GPUI".into()),
                    ..Default::default()
                }),
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            |window, cx| cx.new(|cx| ChatHistory::new(window, cx)),
        )
        .expect("failed to open GPUI chat history window");
        cx.activate(true);
        emit_window_shown();
    });
}
