# All-app fairness audit — September 13, 2026

**The full chat-history suite does not currently meet the “equally competent implementations, comparable parsing and rendering work” standard.** Matching normalized content digests establishes document-content agreement, not equivalent presentation, viewport work, or deferred decoding. The previous broad tables must not be described as isolated framework performance comparisons.

This is a source and focused-test audit of the current working tree, including earlier uncommitted native alignment work. It covers all nine chat-history targets, including Tauri's source despite its exclusion from recent runs. It also checks the ten Hello World targets separately. No new performance measurements or successful whole-suite screenshot acceptance were produced. This audit records required implementation work; it does not represent that work as completed.

> Follow-up: the [unlocked native visual check](RN_VISUAL_ALIGNMENT.md#september-13-unlocked-verification) now covers RN/AppKit/SwiftUI initial/top/switched dark viewports and fixes an AppKit inset plus a SwiftUI list regression. Light/narrow checks and the broader corrections below remain outstanding. The matrix describes the audit snapshot.

> Implementation follow-up: [other-app alignment and verification](ALL_APPS_ALIGNMENT.md) records the completed correction pass and remaining platform differences. The matrix below remains the historical audit snapshot.

## Per-app assessment

| App | Transcript preparation | Markdown rendering | Visual/workload status |
| --- | --- | --- | --- |
| React Native | C++ range-backed document; deferred message text and native Markdown block IDs; metadata supplied on demand | Enriched Markdown, GitHub flavor; native rich text, code panes and real tables; chat build disables code highlighting | Reference contract, not presumed perfect; final clean screenshots still needed |
| AppKit | Idiomatic Swift range reader and deferred document fields by default; optional C++ diagnostic path | Shared Swift Markdown AST/TextKit renderer, code/table subviews | Recent alignment implemented and layout-tested; live glass and full viewport acceptance pending |
| SwiftUI | Same Swift document model as AppKit | Same shared Markdown renderer inside lazy SwiftUI rows | Same pending visual acceptance; framework lookahead differs legitimately |
| Electron | Byte scan, line decoding and full JSON parsing in Node worker; all normalized rows returned through worker/main/renderer | React Markdown + remark-gfm, rendered for virtualized rows | Different widths, spacing, code/table presentation; no composer or matching overlay chrome; eager document workload |
| Tauri | Rust reads and validates full UTF-8 source, parses JSON records and constructs all rows; returns full document via IPC | Exactly the shared web renderer used by Electron | Same visual gaps; eager document workload; runtime readiness remains unverified |
| Deno WebView | Shared TypeScript parser/catalog in Deno, worker builds full document and bindings deliver it to WebKit | Exactly the shared web renderer | Same gaps; browser scheduling differs from Chromium |
| Deno CEF | Same Deno document path as WebView | Same web renderer hosted by CEF | Same gaps; shared UI source does not make WebKit/CEF rendering costs identical |
| Flutter | Dart byte scan and per-line JSON decoding in reusable isolate; complete document returned | flutter_markdown_plus, default GitHub flavor; real rich text/tables, no syntax highlighter | **Different row order/initial viewport**, fixed-width layout, default Markdown styling, missing composer/glass |
| GPUI | Shared eager Rust document, background task; per-row Markdown blocks cached in OnceLock | pulldown-cmark converted to simplified custom blocks | **Tables flattened to text**, different collapsed tool/file content, different layout, missing composer/glass |

“Eager” above refers to transcript strings/rows, not pre-rendering every Markdown message. Electron/Deno/Tauri virtualize rendered rows; Flutter builds indexed rows; GPUI lazily parses Markdown blocks. Those existing optimizations should be retained.

## Blocking findings

### 1. Flutter measures a different viewport

In `_TranscriptState.build`, `ScrollablePositionedList.builder` uses `initialScrollIndex: 0`, supplies `rows[length - 1 - index]`, and does not set `reverse`. The installed list package defaults to `reverse: false` and `initialAlignment: 0`. Consequently the latest row begins at the top and older rows follow downward. RN instead displays a chronological transcript anchored at the bottom. Flutter's `jumpToTop` jumps to the final list index, which represents the oldest row at the other end of this inverted data order.

This is a source-confirmed workload mismatch, not a claim inferred from startup numbers. A matching digest cannot detect it because the digest uses the model array, not the displayed order. Fix chronological presentation and the bottom/top anchor together; merely changing an index or adding `reverse` without revalidating positioning is insufficient. Test short, long and over-one-screen final messages, then capture the same first/last visible row IDs as RN.

Source: [Flutter transcript](../apps/chat-history-flutter/lib/main.dart), `_TranscriptState`, around lines 786–859. Installed dependency: `scrollable_positioned_list` 0.3.8, constructor defaults.

### 2. GPUI performs materially different Markdown and collapsed-row rendering

`markdown::blocks` emits table cells separated by the literal string `  │  ` and discards column alignment. `render_markdown` draws the result as one monospace text block. It does not lay out independent cells, wrap within columns, or implement RN's content-driven horizontal table scroller. Its existing “preserves tables” test explicitly accepts this flattened representation; a passing test therefore does not establish rendering equivalence.

Code language is inserted into the code's text instead of a separate fixed header. There is no matching code copy control or horizontal pane. Lists/task markers and horizontal rules are literal characters; task rows retain the bullet plus checkbox text. Soft breaks become newlines and hard breaks become two newlines. Quote state is one block-kind flag, which cannot preserve arbitrary nested quote/block structure. Inline code gets background styling but no code-font override in `styled_markdown_text`. These are real differences from a complete rich Markdown renderer, not harmless antialiasing variation.

Collapsed tools display a 180-character preview, while RN displays only the label/chevron. Collapsed file cards show just a count, whereas RN includes totals and the first three files. User bubbles have neither RN's right-aligned compact geometry nor its percentage-width policy. Headings are 24/20/17 rather than the reference styles, block gaps are seven points, and the transcript is capped at 860 points.

Required correction: retain a structured Markdown model and render actual table cells, proper nested blocks, matching code panes, and the same collapsed contents. Keep ordinary GPUI text/layout primitives and lazy list behavior. A painted imitation of a table is not an equivalent workload.

Sources: [GPUI Markdown](../apps/chat-history-gpui/src/markdown.rs), `blocks`; [GPUI UI](../apps/chat-history-gpui/src/main.rs), `render_row`, `render_markdown`, `styled_markdown_text`.

### 3. The non-Swift comparison backends still do substantially more eager document work

RN retains source ranges and resolves message text through the document/native Markdown registry. The current default Swift implementation follows that design using Swift byte ranges and deferred text. In contrast:

- Electron and both Deno apps scan bytes, decode each line, run `JSON.parse`, construct every normalized row/string and transfer the complete document. This avoids a full-file string split in the production path, but is not the lazy RN document model.
- Flutter similarly scans byte ranges and decodes each line, then `jsonDecode` constructs full objects and all rows before isolate delivery.
- Tauri and GPUI use the shared Rust parser: `fs::read`, `String::from_utf8`, line slices, `serde_json::Value` for each record, and a complete `Vec<ChatRow>`. GPUI shares it in-process with `Arc`; Tauri serializes a full result to the webview.

These implementations do unnecessary work for the stated large-history initial-viewport scenario compared with the reference. Neither the precise startup cost nor the memory impact can be attributed to the frameworks alone while this remains.

Required correction: equivalent selective indexing and deferred message/preview materialization in the normal language of each app. For hosts with process boundaries, retain document ownership in the worker/backend and expose metadata plus bounded, batched row requests. Avoid one IPC round trip per field. Release prior documents/caches on switch consistently. Retain full-source validation/semantic correctness; do not shortcut known fixture IDs or omit validation for speed. Use ordinary buffering/async scheduling; a shared C++ backend is not required for fairness.

Sources: [TypeScript parser](../apps/chat-history-electron/src/parser.ts), `openChatFile`, `parseCodex`, `parseClaude`; [Electron worker/IPC](../apps/chat-history-electron/src/main.ts); [Deno runtime](../apps/chat-history-deno/src/runtime.ts); [Rust parser](../packages/chat-history-rust/src/parser.rs), `open_chat_file`; [Tauri commands](../apps/chat-history-tauri/src-tauri/src/lib.rs); [Dart parser](../apps/chat-history-flutter/lib/parser.dart); [Dart worker](../apps/chat-history-flutter/lib/parser_worker.dart); [Swift document](../packages/chat-history-swift/Sources/ChatHistoryCore/SwiftDocument.swift).

### 4. Shared web UI and Flutter do not match the reference style or visible content area

Electron, Tauri and both Deno variants directly import the same renderer/CSS, so one shared UI correction can cover all four. Current web rows have an 860-point cap, 22-point side padding, different bubble padding and default browser paragraph/list margins. The 46-point header consumes space above the list; it always shows catalog timing and a settings button. There is no composer, top overlay or 112-point bottom clearance. Prose inherits 16-point text with line-height 1.55, rather than 15/22.

Web Markdown already has real semantic tables and GFM parsing, and unhighlighted horizontally scrollable code. However, its code blocks lack the separate language/copy header and reference styling; automatic HTML table sizing differs from RN's capped content measurement. It needs adaptation, not replacement with plain text. Browser text selection is available.

Flutter uses the same 860-point outer cap, hardcoded 705/790 message limits, a 46-point header and Material-derived colors/Markdown defaults. Its installed Markdown package provides horizontal code scrolling and real tables, but the default table columns are `FlexColumnWidth`, not the reference's content-driven width policy. Code headers/copy controls are absent. `SelectionArea` is present and no syntax highlighter is configured. It needs explicit style/table/code builders and responsive message widths, not a reduced Markdown renderer.

Sources: [Shared web renderer](../apps/chat-history-electron/src/renderer.tsx), [CSS](../apps/chat-history-electron/src/styles.css), [Tauri import](../apps/chat-history-tauri/src/bootstrap.ts), [Deno import](../apps/chat-history-deno/src/bootstrap.ts), [Flutter UI](../apps/chat-history-flutter/lib/main.dart), `_Content`, `_MessageRow`. Dependency behavior checked in installed `flutter_markdown_plus` 1.0.12 `widget.dart`, `style_sheet.dart`, and `builder.dart`.

### 5. Native window chrome and discovery still need cross-app acceptance

AppKit/SwiftUI now use the native glass implementation, but live acceptance is unfinished. September 13 captures were obstructed by a Documents permission alert; the RN capture did not show a loaded reference transcript. None is a successful parity screenshot. This is separate from the earlier locked-display failure.

Electron/Tauri/Deno use ordinary host windows; Flutter uses a standard NSWindow around its view controller; GPUI adds its own sidebar/header UI. Their current titlebar/content dimensions are not normalized merely by requesting 1280×720: some constructors specify content size while others specify window bounds. Match the actual captured client/transcript rectangles, not just constructor arguments.

Use genuine native material where the platform integration supports it, and a documented platform-appropriate translucent blur where it does not. Do not force every framework through a custom AppKit renderer just to reproduce glass. Exact glass pixels may differ; header/composer dimensions, overlap, opacity behavior and visible transcript contents should still agree. Compare glass-enabled product results separately from any optional uniform opaque control; never disable glass for only one ranked app.

Catalog discovery should remain idiomatic, as previously agreed, with matching inclusion/filtering semantics. One specific correctness issue remains in Rust: `is_codex_subagent` reads a capped 64 KiB prefix into a UTF-8 String before selecting its first line. A cap that bisects a later multibyte character causes `read_to_string` to fail and returns “not a subagent,” even if the first metadata line was valid. The current Swift code already isolates the first line before decoding. TS/Dart also decode the entire prefix unnecessarily, though their replacement-decoding behavior avoids that exact failure. Standardize byte-first first-line extraction and add the boundary regression across implementations.

Sources: [Rust catalog](../packages/chat-history-rust/src/catalog.rs), `is_codex_subagent`; [TS catalog](../apps/chat-history-electron/src/catalog.ts); [Dart catalog](../apps/chat-history-flutter/lib/catalog.dart); [Native alignment status](RN_VISUAL_ALIGNMENT.md).

## Acceptance contract for the correction pass

These rules apply to all product apps, including the RN reference. They define equivalent observable work without requiring identical internals.

| Area | Required behavior |
| --- | --- |
| Data | Same pinned bytes, normalized rows, chronology, selected chats, catalog inclusion rules and benchmark settings |
| Document model | Selective indexing; deferred text/preview work; lazy viewport Markdown; reasonable caching and document release; no fixture-specific preload |
| Geometry | Same measured window/client/transcript bounds; nominal 260-point sidebar, 52-point title region, 20-point message insets; assistant 92%, user 82% of available row width; user inner padding 16×12 |
| Insets/composer | 64-point initial top clearance; 112-point bottom clearance; 60-point composer, maximum width 860, 20-point bottom gap, 26-point corners; same placeholder and disabled send control |
| Text | System font, prose 15/22; headings/reference margins; inline code 13, fenced code 12/18; same theme tokens, not default Material/browser approximations |
| Markdown | Real GFM headings, emphasis, links, code, nested lists/tasks/quotes, rules and independent aligned table cells; equivalent horizontal overflow; syntax highlighting off everywhere |
| Code/tables | Fixed language/copy header; complete unwrapped code; rounded border; tables with content-driven columns, 60-point minimum and 300-point text cap + 16-point padding, 6-point vertical cell padding |
| Collapsed rows | Tool preview hidden; same label/chevron/divider; file totals plus first three files; same image-omitted policy |
| Scenarios | Initial bottom, actual chronological top, switched bottom; verify visible row IDs and text bounds, not only document digests or nonempty rows |
| Images | Disabled for this benchmark, including embedded Markdown image policy; do not claim image-enabled parity without a separate acceptance pass |
| Timing | Same launch policy, fixture checks, settled-content detector, release builds, warmups and rotating trials; separate unrecorded memory sampling; quiet machine |

Framework-driven lookahead, native text shaping, list recycling, backend IPC and platform composition are legitimate remaining costs once observable work and basic application strategy are aligned. Do not force identical overscan counts or tune each list to this fixture. Log materialized/Markdown-parsed row IDs in diagnostic runs to identify accidental eager work; keep instrumentation out of scored runs.

The correction pass should proceed in this order: fix chronology and collapsed contents; align backend document strategies; align shared web/Flutter/GPUI styles and structured renderers; complete native and cross-platform visual acceptance; then rerun and publish fresh measurements. Existing timings cannot predict the result.

For acceptance, exercise a small synthetic transcript containing nested quotes/lists/tasks, long code, aligned tables, inline styles, file changes and omitted images, then the two pinned large histories. Capture initial/top/switched viewports at the same measured size and appearance, plus narrow/light/dark checks. Structural assertions should check table cells, ordering, selection/copy and overflow; screenshot checks should tolerate platform antialiasing and documented material differences.

## Hello World audit

The ten targets are AppKit, SwiftUI, standalone RN, Legend Shell, Electron, Tauri, Flutter, GPUI, Deno WebView and Deno CEF. Their source uses the same centered “Hello, world!” greeting at 32 points on white with #202124 text. The web hosts share `packages/hello-world-web`; RN standalone and Legend Shell have separate app sources; Flutter/AppKit/SwiftUI/GPUI use their own text primitives. No transcript parsing or Markdown workload belongs in these baselines.

This is substantially closer to equivalent work than the product suite. Keep Legend Shell separately labeled: it intentionally measures shell infrastructure in addition to RN, while standalone RN is the framework baseline. Font fallback, actual client-area dimensions and platform titlebar appearance still need capture-based confirmation; source inspection is not pixel certification. Do not add a chat composer or Markdown dependencies merely to align Hello World with the product.

## Evidence and limits

Fresh checks on this working tree:

- Shared Rust parser/catalog: **6 tests passed**.
- Flutter parser/catalog/reused-isolate suite: **5 tests passed**.
- GPUI Markdown suite: **2 tests passed**; as noted above, its table expectation currently validates flattening, not parity.
- Two attempted Bun test invocations stalled before reporting test cases and were terminated; no fresh TypeScript pass is claimed.
- Previous native pass: 21 Swift tests and production-source layout harnesses passed; these were not repeated for this source-only audit.
- Prior September 12 content-digest evidence remains historical evidence for those builds. No new all-app launch/digest/video pass was performed here, and no old timing or fixture bytes were changed.

The [audit manifest](ALL_APPS_FAIRNESS_AUDIT.sources.json) records the inspected source hashes and test outcomes. It is not an automated parity certificate. Passing parser tests does not resolve the rendering or viewport blockers above.
