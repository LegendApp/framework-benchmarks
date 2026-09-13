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
    ChatDocument, ChatRow, ChatSummary, get_recent_chat_catalog, normalized_content_digest,
    open_chat_file, user_home,
};
use chrono::{Local, TimeZone};
use gpui::{
    AnyElement, AnyWindowHandle, App, Application, Bounds, Context, Div, FontStyle, FontWeight,
    HighlightStyle, InteractiveText, ListAlignment, ListOffset, ListState, Render,
    StrikethroughStyle, StyledText, Task, TitlebarOptions, UnderlineStyle, Window,
    WindowAppearance, WindowBounds, WindowOptions, div, img, list, prelude::*, px, rgb, rgba, size,
};
use markdown::{BlockKind, InlineKind, MarkdownBlock, blocks};
use settings::Settings;

#[derive(Clone, Copy)]
struct Palette {
    accent: gpui::Rgba,
    background: gpui::Rgba,
    border: gpui::Rgba,
    code: gpui::Rgba,
    code_background: gpui::Rgba,
    code_text: gpui::Rgba,
    inline_text: gpui::Rgba,
    quote: gpui::Rgba,
    quote_border: gpui::Rgba,
    table_header: gpui::Rgba,
    table_alt: gpui::Rgba,
    muted: gpui::Rgba,
    sidebar: gpui::Rgba,
    text: gpui::Rgba,
    user: gpui::Rgba,
}

impl Palette {
    fn new(dark: bool) -> Self {
        if dark {
            Self {
                accent: rgb(0x60a5fa),
                background: rgb(0x191a1b),
                border: rgb(0x3e4042),
                code: rgb(0x2d2e30),
                code_background: rgb(0x111213),
                code_text: rgb(0xf5f5f5),
                inline_text: rgb(0xeb5757),
                quote: rgb(0x202122),
                quote_border: rgb(0x6f7377),
                table_header: rgb(0x2a2b2d),
                table_alt: rgb(0x1f2021),
                muted: rgb(0xa3a3a3),
                sidebar: rgba(0x252528cc),
                text: rgb(0xf5f5f5),
                user: rgb(0x2d2e30),
            }
        } else {
            Self {
                accent: rgb(0x2563eb),
                background: rgb(0xf5f6f8),
                border: rgb(0xd1d5db),
                code: rgb(0xe5e7eb),
                code_background: rgb(0x111827),
                code_text: rgb(0xf9fafb),
                inline_text: rgb(0x111827),
                quote: rgb(0xf8fafc),
                quote_border: rgb(0x94a3b8),
                table_header: rgb(0xf3f4f6),
                table_alt: rgb(0xf9fafb),
                muted: rgb(0x6b7280),
                sidebar: rgba(0xffffffb3),
                text: rgb(0x111827),
                user: rgb(0xf3f4f6),
            }
        }
    }
}

struct ChatHistory {
    benchmark: Option<Benchmark>,
    benchmark_discovery_ms: Option<f64>,
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
        let benchmark = Benchmark::load().unwrap_or_else(|error| {
            eprintln!("{error}");
            None
        });
        let settings = benchmark
            .as_ref()
            .map(|benchmark| Settings {
                appearance: benchmark
                    .appearance
                    .clone()
                    .unwrap_or_else(|| "system".into()),
                load_images: benchmark.load_images,
                restore_selection: false,
                ..Settings::default()
            })
            .unwrap_or_else(Settings::load);
        let mut view = Self {
            benchmark,
            benchmark_discovery_ms: None,
            catalog_loaded: false,
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
            summaries: Arc::new(Vec::new()),
            window: window.window_handle(),
        };
        view.refresh_catalog(cx);
        view
    }

    fn refresh_catalog(&mut self, cx: &mut Context<Self>) {
        self.loading = true;
        self.error = None;
        let target_ids = self.benchmark.as_ref().map(|benchmark| {
            benchmark
                .targets
                .iter()
                .map(|target| (target.id.clone(), target.provider.clone()))
                .collect::<Vec<_>>()
        });
        let discovery_started = Instant::now();
        let limit = if target_ids.is_some() {
            usize::MAX
        } else {
            self.settings.recent_chat_limit
        };
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
                    if target_ids.is_some() {
                        view.benchmark_discovery_ms =
                            Some(discovery_started.elapsed().as_secs_f64() * 1000.0);
                    }
                    view.catalog_loaded = true;
                    view.catalog_ms = catalog.native_total_ms;
                    let resolved_targets = target_ids.as_ref().map(|ids| {
                        ids.iter()
                            .map(|(id, provider)| {
                                catalog
                                    .summaries
                                    .iter()
                                    .find(|item| item.id == *id && item.provider == *provider)
                                    .cloned()
                            })
                            .collect::<Vec<_>>()
                    });
                    let missing_target = resolved_targets
                        .as_ref()
                        .is_some_and(|targets| targets.iter().any(Option::is_none));
                    if missing_target {
                        view.loading = false;
                        view.error = Some(
                            "A pinned benchmark chat was not found during native history discovery"
                                .into(),
                        );
                        cx.notify();
                        return;
                    }
                    let mut visible = catalog
                        .summaries
                        .into_iter()
                        .take(view.settings.recent_chat_limit)
                        .collect::<Vec<_>>();
                    if let Some(targets) = &resolved_targets {
                        for target in targets.iter().flatten() {
                            if !visible.iter().any(|summary| summary.id == target.id) {
                                visible.push(target.clone());
                            }
                        }
                    }
                    view.summaries = Arc::new(visible);
                    let initial = resolved_targets
                        .as_ref()
                        .and_then(|targets| targets.first().and_then(Clone::clone))
                        .or_else(|| {
                            selected_id
                                .as_deref()
                                .and_then(|id| view.summaries.iter().find(|item| item.id == id))
                                .cloned()
                        })
                        .or_else(|| view.summaries.first().cloned());
                    view.loading = false;
                    if let Some(summary) = initial {
                        view.select(summary, target_ids.as_ref().map(|_| "initial"), cx);
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
                            view.markdown =
                                Arc::new((0..row_count).map(|_| OnceLock::new()).collect());
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
            "discoveryMs": if pending.phase == "initial" { self.benchmark_discovery_ms } else { None },
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
        let benchmark_for_digest = benchmark.clone();
        let document_for_digest = document.clone();
        cx.background_spawn(async move {
            let _ = benchmark_for_digest.emit(serde_json::json!({
                "contentDigest": normalized_content_digest(&document_for_digest.rows),
                "name": "contentDigest",
                "path": document_for_digest.path,
                "phase": pending.phase,
            }));
        })
        .detach();
        if pending.phase != "initial" {
            return;
        }
        let Some(target) = benchmark.targets.get(1) else {
            return;
        };
        let Some(summary) = self
            .summaries
            .iter()
            .find(|summary| summary.id == target.id && summary.provider == target.provider)
            .cloned()
        else {
            return;
        };
        let top_delay_ms = benchmark.top_delay_ms;
        let switch_delay_ms = benchmark.switch_delay_ms;
        let benchmark = benchmark.clone();
        let path = document.path.clone();
        let generation = pending.generation;
        self.loading_task = Some(cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(Duration::from_millis(top_delay_ms))
                .await;
            let started = Instant::now();
            let window = this
                .update(cx, |view, cx| {
                    if generation == view.generation {
                        view.list_state.scroll_to(ListOffset {
                            item_ix: 0,
                            offset_in_item: px(0.0),
                        });
                        cx.notify();
                        Some(view.window)
                    } else {
                        None
                    }
                })
                .ok()
                .flatten();
            let Some(window) = window else { return };
            let _ = window.update(cx, |root, window, cx| {
                cx.notify(root.entity_id());
                window.refresh();
            });
            cx.background_executor()
                .timer(Duration::from_millis(50))
                .await;
            let _ = benchmark.emit(serde_json::json!({
                "durationMs": started.elapsed().as_secs_f64() * 1000.0,
                "name": "viewportReady",
                "path": path,
                "phase": "top",
            }));
            cx.background_executor()
                .timer(Duration::from_millis(switch_delay_ms))
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
                                .truncate()
                                .text_size(px(13.0))
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
            .w(px(252.0))
            .ml(px(8.0))
            .my(px(8.0))
            .rounded(px(20.0))
            .overflow_hidden()
            .flex_none()
            .flex()
            .flex_col()
            .bg(palette.sidebar)
            .border_1()
            .border_color(palette.border)
            .child(
                div()
                    .h(px(44.0))
                    .flex_none()
                    .flex()
                    .items_center()
                    .px(px(16.0))
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(""),
            )
            .child(
                div()
                    .id("sidebar-scroll")
                    .flex_1()
                    .min_h(px(0.0))
                    .overflow_y_scroll()
                    .children(entries),
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
            .absolute()
            .top_0()
            .left_0()
            .right_0()
            .bg(palette.sidebar)
            .h(px(52.0))
            .flex_none()
            .flex()
            .items_center()
            .justify_between()
            .px(px(20.0))
            .border_b_1()
            .border_color(palette.border)
            .child(div().font_weight(FontWeight::SEMIBOLD).child(title))
            .child(
                div().text_xs().text_color(palette.muted).child(
                    div()
                        .id("open-settings")
                        .cursor_pointer()
                        .on_click(cx.listener(|view, _, _, cx| {
                            view.settings_open = true;
                            cx.notify();
                        }))
                        .child("⚙"),
                ),
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
                div()
                    .pt(px(if index == 0 { 64.0 } else { 0.0 }))
                    .pb(px(if index + 1 == document.rows.len() {
                        112.0
                    } else {
                        0.0
                    }))
                    .child(render_row(
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
                    ))
                    .into_any_element()
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
            .when(self.settings.show_performance_metrics, |content| {
                content.when_some(self.document.as_ref(), |content, document| {
                    content.child(
                        div()
                            .h(px(28.0))
                            .flex_none()
                            .flex()
                            .items_center()
                            .px(px(20.0))
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
            .relative()
            .child(body)
            .child(header)
            .child(div().absolute().bottom(px(20.0)).left(px(24.0)).right(px(24.0)).flex().justify_center().child(
                div().w_full().max_w(px(860.0)).h(px(60.0)).rounded(px(26.0)).border_1().border_color(palette.border).bg(palette.sidebar).px(px(16.0)).flex().items_center().justify_between()
                    .child(div().text_size(px(15.0)).text_color(palette.muted).child("Send a test message that doesn't actually do anything"))
                    .child(div().size(px(36.0)).rounded_full().bg(rgba(0x60a5fa4d)).text_color(rgb(0xffffff)).flex().items_center().justify_center().child("↑"))
            ))
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
            .font_family(".AppleSystemUIFont")
            .text_size(px(15.0))
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
                .px(px(20.0))
                .py(px(8.0))
                .child(
                    div()
                        .id(gpui::SharedString::from(format!("tool-{id}")))
                        .py(px(12.0))
                        .border_b_1()
                        .border_color(palette.border)
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
                                .gap(px(8.0))
                                .text_size(px(14.0))
                                .line_height(px(20.0))
                                .text_color(palette.muted)
                                .font_weight(FontWeight::MEDIUM)
                                .child(row.tool_name.clone())
                                .child(if tool_expanded { "⌄" } else { "›" }),
                        )
                        .when(tool_expanded && !row.tool_preview.is_empty(), |tool| {
                            tool.child(
                                div()
                                    .mt(px(16.0))
                                    .text_size(px(14.0))
                                    .line_height(px(24.0))
                                    .text_color(palette.muted)
                                    .child(row.tool_preview.to_string()),
                            )
                        }),
                )
                .into_any_element()
        }
        "files" => {
            let id = row.id.clone();
            let id_for_click = id.clone();
            let changes = row.file_changes.clone();
            let hidden_files = changes.len().saturating_sub(3);
            div()
                .mx_auto()
                .w_full()
                .px(px(20.0))
                .py(px(8.0))
                .child(
                    div()
                        .id(gpui::SharedString::from(format!("files-{id}")))
                        .rounded(px(12.0))
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
                                .p(px(16.0))
                                .flex()
                                .items_center()
                                .gap(px(12.0))
                                .child(
                                    div()
                                        .size(px(40.0))
                                        .flex_none()
                                        .rounded(px(8.0))
                                        .bg(palette.code)
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .text_size(px(22.0))
                                        .child("+"),
                                )
                                .child(
                                    div()
                                        .flex()
                                        .flex_col()
                                        .gap(px(4.0))
                                        .child(
                                            div()
                                                .text_size(px(16.0))
                                                .font_weight(FontWeight::SEMIBOLD)
                                                .child(format!(
                                                    "Edited {} {}",
                                                    changes.len(),
                                                    if changes.len() == 1 {
                                                        "file"
                                                    } else {
                                                        "files"
                                                    }
                                                )),
                                        )
                                        .child(
                                            div()
                                                .flex()
                                                .gap(px(8.0))
                                                .text_size(px(14.0))
                                                .child(div().text_color(rgb(0x16843c)).child(
                                                    format!(
                                                        "+{}",
                                                        changes
                                                            .iter()
                                                            .map(|file| file.additions)
                                                            .sum::<usize>()
                                                    ),
                                                ))
                                                .child(div().text_color(rgb(0xc22f2f)).child(
                                                    format!(
                                                        "−{}",
                                                        changes
                                                            .iter()
                                                            .map(|file| file.deletions)
                                                            .sum::<usize>()
                                                    ),
                                                )),
                                        ),
                                ),
                        )
                        .map(|card| {
                            card.children(
                                changes
                                    .into_iter()
                                    .take(if files_expanded { usize::MAX } else { 3 })
                                    .map(|file| {
                                        div()
                                            .px(px(16.0))
                                            .py(px(12.0))
                                            .border_t_1()
                                            .border_color(palette.border)
                                            .flex()
                                            .justify_between()
                                            .text_sm()
                                            .child(
                                                div()
                                                    .flex_1()
                                                    .min_w(px(0.0))
                                                    .truncate()
                                                    .child(file.path),
                                            )
                                            .child(format!(
                                                "+{}  −{}",
                                                file.additions, file.deletions
                                            ))
                                    }),
                            )
                        })
                        .when(hidden_files > 0, |card| {
                            card.child(
                                div()
                                    .mt(px(8.0))
                                    .text_size(px(13.0))
                                    .text_color(palette.muted)
                                    .child(if files_expanded {
                                        "Show less".to_string()
                                    } else {
                                        format!("Show {hidden_files} more files")
                                    }),
                            )
                        }),
                )
                .into_any_element()
        }
        _ => {
            let is_user = row.kind == "user";
            div()
                .mx_auto()
                .w_full()
                .px(px(20.0))
                .py(px(if is_user { 8.0 } else { 12.0 }))
                .flex()
                .when(is_user, |row| row.justify_end())
                .child(
                    div()
                        .max_w(gpui::relative(if is_user { 0.82 } else { 0.92 }))
                        .when(!is_user, |message| message.w(gpui::relative(0.92)))
                        .min_w(px(0.0))
                        .when(is_user, |message| {
                            message
                                .px(px(16.0))
                                .py(px(12.0))
                                .rounded(px(16.0))
                                .bg(palette.user)
                        })
                        .child(render_markdown(
                            &row.id,
                            markdown,
                            palette,
                            load_images,
                            window,
                        ))
                        .when(
                            row.has_image_placeholder
                                || (!load_images && !row.image_sources.is_empty()),
                            |message| {
                                message.child(
                                    div()
                                        .mt(px(8.0))
                                        .text_sm()
                                        .text_color(palette.muted)
                                        .child("Image or attachment omitted"),
                                )
                            },
                        )
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
    window: &Window,
) -> Div {
    let row_id = row_id.to_string();
    div()
        .flex()
        .flex_col()
        .gap(px(0.0))
        .text_size(px(15.0))
        .line_height(px(22.0))
        .children(blocks.iter().cloned().enumerate().map(|(index, block)| {
            let text = styled_markdown_text(&block, palette, format!("markdown-{row_id}-{index}"));
            let images = block.images.clone();
            let element = match block.kind {
                BlockKind::Heading(level) => div()
                    .text_size(px(match level {
                        1 => 22.0,
                        2 => 19.0,
                        3 => 20.0,
                        4 => 18.0,
                        5 => 16.0,
                        _ => 14.0,
                    }))
                    .line_height(px(match level {
                        1 | 3 => 28.0,
                        2 => 25.0,
                        4 => 26.0,
                        5 => 24.0,
                        _ => 22.0,
                    }))
                    .font_weight(FontWeight::BOLD)
                    .child(text)
                    .into_any_element(),
                BlockKind::Code => {
                    let copy_text = block.text.clone();
                    div()
                        .w_full()
                        .rounded(px(7.0))
                        .border_1()
                        .border_color(palette.border)
                        .bg(palette.code_background)
                        .text_color(palette.code_text)
                        .overflow_hidden()
                        .child(
                            div()
                                .h(px(26.0))
                                .px(px(12.0))
                                .flex()
                                .items_center()
                                .justify_between()
                                .text_size(px(11.0))
                                .text_color(palette.muted)
                                .child(if block.language.is_empty() {
                                    "Code".to_string()
                                } else {
                                    capitalize(&block.language)
                                })
                                .child(
                                    div()
                                        .id(gpui::SharedString::from(format!(
                                            "copy-{row_id}-{index}"
                                        )))
                                        .cursor_pointer()
                                        .child("Copy")
                                        .on_click(move |_, _, cx| {
                                            cx.write_to_clipboard(gpui::ClipboardItem::new_string(
                                                copy_text.clone(),
                                            ))
                                        }),
                                ),
                        )
                        .child(
                            div()
                                .id(gpui::SharedString::from(format!("code-{row_id}-{index}")))
                                .overflow_x_scroll()
                                .p(px(12.0))
                                .font_family("Menlo")
                                .text_size(px(12.0))
                                .line_height(px(18.0))
                                .whitespace_nowrap()
                                .child(text),
                        )
                        .into_any_element()
                }
                BlockKind::Table => {
                    // Share each measured column width across independently styled cells.
                    let columns = block.cells.iter().map(Vec::len).max().unwrap_or(0);
                    let widths = (0..columns)
                        .map(|column| {
                            block
                                .cells
                                .iter()
                                .enumerate()
                                .filter_map(|(row, cells)| {
                                    cells.get(column).map(|cell| (row, cell))
                                })
                                .map(|(row, cell)| {
                                    let mut cell = cell.clone();
                                    if row == 0 {
                                        cell.kind = BlockKind::Heading(6);
                                    }
                                    // Measure the same styled runs used to paint the cell.
                                    // Italics, bold and Menlo can exceed plain system text.
                                    window
                                        .text_system()
                                        .shape_text(
                                            cell.text.clone().into(),
                                            px(14.0),
                                            &markdown_text_runs(&cell, palette),
                                            None,
                                            None,
                                        )
                                        .map(|lines| {
                                            lines
                                                .iter()
                                                .map(|line| f32::from(line.width()))
                                                .fold(0.0_f32, f32::max)
                                        })
                                        .unwrap_or(300.0)
                                        .ceil()
                                })
                                .fold(44.0_f32, f32::max)
                                .min(300.0)
                                + 16.0
                        })
                        .collect::<Vec<_>>();
                    div()
                        .id(gpui::SharedString::from(format!("table-{row_id}-{index}")))
                        .overflow_x_scroll()
                        .text_size(px(14.0))
                        .line_height(px(20.0))
                        .child(div().flex().flex_col().w(px(widths.iter().sum())).children(
                            block.cells.iter().enumerate().map(|(row_index, cells)| {
                                div().flex().children(cells.iter().enumerate().map(
                                    |(column, cell)| {
                                        div()
                                            .w(px(widths[column]))
                                            .flex_none()
                                            .px(px(8.0))
                                            .py(px(6.0))
                                            .relative()
                                            // Draw the border without subtracting from the
                                            // measured text width or the cell padding.
                                            .child(
                                                div()
                                                    .absolute()
                                                    .inset_0()
                                                    .border_1()
                                                    .border_color(palette.border),
                                            )
                                            .when(row_index == 0, |cell| {
                                                cell.bg(palette.table_header)
                                                    .font_weight(FontWeight::SEMIBOLD)
                                            })
                                            .when(row_index > 0 && row_index % 2 == 0, |cell| {
                                                cell.bg(palette.table_alt)
                                            })
                                            .map(|cell| match block.alignments.get(column) {
                                                Some(pulldown_cmark::Alignment::Center) => {
                                                    cell.text_center()
                                                }
                                                Some(pulldown_cmark::Alignment::Right) => {
                                                    cell.text_right()
                                                }
                                                _ => cell,
                                            })
                                            .child(styled_markdown_text(
                                                &{
                                                    let mut cell = cell.clone();
                                                    if row_index == 0 {
                                                        cell.kind = BlockKind::Heading(6);
                                                    }
                                                    cell
                                                },
                                                palette,
                                                format!(
                                                    "cell-{row_id}-{index}-{row_index}-{column}"
                                                ),
                                            ))
                                    },
                                ))
                            }),
                        ))
                        .into_any_element()
                }
                BlockKind::Rule => div()
                    .h(px(1.0))
                    .w_full()
                    .bg(palette.border)
                    .my(px(8.0))
                    .into_any_element(),
                BlockKind::Body => div()
                    .child(text)
                    .when(!load_images && !images.is_empty(), |body| {
                        body.child(
                            div()
                                .text_size(px(12.0))
                                .text_color(palette.muted)
                                .child("Image or attachment omitted"),
                        )
                    })
                    .when(load_images, |body| {
                        body.children(images.into_iter().map(|image| {
                            div()
                                .mt(px(8.0))
                                .child(img(image.source).max_h(px(360.0)).rounded(px(8.0)))
                        }))
                    })
                    .into_any_element(),
            };
            let mut container = div().child(element);
            let margin = if index + 1 == blocks.len() {
                0.0
            } else {
                match block.kind {
                    BlockKind::Heading(1) => 8.0,
                    BlockKind::Heading(2) => 6.0,
                    BlockKind::Heading(_) => 4.0,
                    _ => 16.0,
                }
            };
            if block.list_depth > 0 {
                container = div()
                    .flex()
                    .pl(px((block.list_depth.saturating_sub(1) * 24) as f32))
                    .child(
                        div()
                            .w(px(24.0))
                            .flex_none()
                            .child(block.marker.clone().unwrap_or_default()),
                    )
                    .child(container.flex_1().min_w(px(0.0)));
            }
            for _ in 0..block.quote_depth {
                container = div()
                    .px(px(12.0))
                    .py(px(8.0))
                    .bg(palette.quote)
                    .border_l(px(3.0))
                    .border_color(palette.quote_border)
                    .text_color(palette.muted)
                    .child(container);
            }
            container.mb(px(margin)).into_any_element()
        }))
}

fn markdown_text_runs(block: &MarkdownBlock, palette: Palette) -> Vec<gpui::TextRun> {
    let mut boundaries = Vec::with_capacity(block.highlights.len() * 2 + 2);
    boundaries.push(0);
    boundaries.push(block.text.len());
    for highlight in &block.highlights {
        boundaries.push(highlight.range.start);
        boundaries.push(highlight.range.end);
    }
    boundaries.sort_unstable();
    boundaries.dedup();

    let mut runs = Vec::new();
    for pair in boundaries.windows(2) {
        let range = pair[0]..pair[1];
        if range.is_empty() {
            continue;
        }
        let mut style = HighlightStyle::default();
        let mut font = gpui::font(if block.kind == BlockKind::Code {
            "Menlo"
        } else {
            ".AppleSystemUIFont"
        });
        if matches!(block.kind, BlockKind::Heading(_)) {
            font.weight = FontWeight::BOLD;
        }
        for highlight in block.highlights.iter().filter(|highlight| {
            highlight.range.start <= range.start && highlight.range.end >= range.end
        }) {
            match highlight.kind {
                InlineKind::Code => {
                    font = gpui::font("Menlo");
                    style.background_color = Some(palette.code.into());
                    style.color = Some(palette.inline_text.into());
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
        if let Some(weight) = style.font_weight {
            font.weight = weight;
        }
        if let Some(font_style) = style.font_style {
            font.style = font_style;
        }
        runs.push(gpui::TextRun {
            len: range.len(),
            font,
            color: style.color.unwrap_or(
                if block.kind == BlockKind::Code {
                    palette.code_text
                } else {
                    palette.text
                }
                .into(),
            ),
            background_color: style.background_color,
            underline: style.underline,
            strikethrough: style.strikethrough,
        });
    }
    runs
}

fn styled_markdown_text(block: &MarkdownBlock, palette: Palette, id: String) -> InteractiveText {
    let text = StyledText::new(block.text.clone()).with_runs(markdown_text_runs(block, palette));
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
                .py(px(8.0))
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
    let minutes =
        ((Local::now().timestamp_millis() as f64 - timestamp_ms).max(0.0) / 60000.0) as u64;
    match minutes {
        0 => "now".into(),
        1..60 => format!("{minutes}m"),
        60..1440 => format!("{}h", minutes / 60),
        1440..10080 => format!("{}d", minutes / 1440),
        _ => Local
            .timestamp_millis_opt(timestamp_ms as i64)
            .single()
            .map(|value| value.format("%b %-d").to_string())
            .unwrap_or_default(),
    }
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
        let bounds = Bounds::centered(
            None,
            size(
                px(std::env::var("CHAT_HISTORY_QA_WIDTH")
                    .ok()
                    .and_then(|value| value.parse::<f32>().ok())
                    .unwrap_or(1280.0)),
                px(720.0),
            ),
            cx,
        );
        cx.open_window(
            WindowOptions {
                focus: true,
                window_background: gpui::WindowBackgroundAppearance::Blurred,
                titlebar: Some(TitlebarOptions {
                    title: Some("Legend Chat History — GPUI".into()),
                    appears_transparent: true,
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
