# Other-app alignment — September 13, 2026

This implements the correction pass from [the all-app audit](ALL_APPS_FAIRNESS_AUDIT.md) for Electron, Tauri, Deno WebView, Deno CEF, Flutter and GPUI. The earlier RN/AppKit/SwiftUI alignment remains the reference. These are application changes and visual QA, not a new performance ranking.

## What changed

| Apps | Document ownership and parsing | Rendering |
| --- | --- | --- |
| Electron / Deno WebView / Deno CEF | TypeScript byte ranges validate JSON without constructing ignored object trees or decoding every message. The worker retains one active document; the UI receives metadata and batched viewport rows. | Shared React Markdown + remark-gfm renderer, virtualized with Legend List. |
| Tauri | Rust source ranges backed by serde `RawValue`; deferred strings, one backend document, bounded row IPC. | The same shared web renderer. |
| Flutter | Dart byte ranges and deferred strings in a reusable isolate; metadata and batched viewport delivery. | Flutter Markdown Plus retains real rich text, nested blocks and GFM tables; explicit styles and a code-pane builder. |
| GPUI | Shared Rust document retained in-process; deferred text and per-row Markdown caching. | Structured pulldown-cmark blocks with real aligned table cells, nested list/task markers, quote borders, rules, styled inline runs and code panes. |

Collapsed tools no longer decode or display previews; expansion requests them separately. File cards show totals and the first three files. Document switches discard the old document/cache and reject obsolete document IDs. Digests are computed after content readiness without populating every viewport cache. Catalog discovery stays in each implementation's normal language, including the first-line UTF-8 boundary correction.

Flutter now uses chronological order and a measured bottom anchor, including when the last message exceeds a window's height. The shared web apps recheck the measured tail after deferred rows load. This fixes a Tauri case where a valid digest and a ready event accompanied the wrong viewport. Going to the top preserves the first row's clearance beneath the overlay header.

All six use the reference's 260-point sidebar column, floating sidebar, 52-point overlay header, 64/112-point transcript insets, 92% assistant width, 82% maximum user width, compact right-aligned user bubbles, and 60-point composer. Prose, headings, fenced code, code headers/copy controls, table width bounds and theme colors now have explicit reference styles. Syntax highlighting remains off. Flutter's Markdown stylesheet and React's Markdown boundary remain stable across unrelated state updates.

Electron and Tauri use their native window material facilities. Flutter uses a native sidebar material beneath its transparent Flutter view, with Flutter blur for the header/composer. GPUI uses its blurred window surface and translucent controls. Deno retains its native titlebar and shared CSS chrome.

## Verification

Final artifact acceptance is recorded in [the source/evidence manifest](ALL_APPS_ALIGNMENT.sources.json). The [comparison viewer](results/2026-09-13-all-app-alignment-final/index.html) provides paired screenshots and saved videos.

- **32 tests passed:** TypeScript 12, shared Rust 9, GPUI 4, Flutter 7. Tests cover parser/provider semantics, deferred descriptors, batched rows, collapsed previews, obsolete document IDs, malformed JSON, first-line UTF-8 boundaries and structured Markdown.
- TypeScript typecheck, Deno entrypoint checks and Flutter analysis passed. All six release bundles built successfully.
- Dark checks use both pinned large histories: **162 / 174 rows**, **8,226 / 10,382 records**, content digests **`3a290b9eb53fa834` / `c27e9dc5a848d7f6`**. Source files were not modified.
- Light checks use an isolated 900-point-wide synthetic catalog with nested lists/tasks/quotes, inline styles, wide code, aligned tables and a final message taller than the window. The expected digests are **`823dcadc7b873332` / `3a8f3a59960396c9`**.
- Recordings cover initial bottom, chronological top and switched bottom. The artifact folders contain screenshots, MP4s, frame timestamps, window bounds, launch records, events and capture scripts. The small synthetic catalog is copied into the light artifact folder.

The narrow captures also verify the final table corrections: preserving React Markdown’s cell-alignment styles and measuring GPUI cells with their actual styled fonts. Dark web/GPUI captures precede those table-only corrections; their parser, viewport policy and visible content are unchanged.

The final Deno captures use the same NSWorkspace launcher as the other apps. An earlier failed QA attempt wrote its event log outside Deno's compiled write permissions; the corrected harness writes to the permitted temporary directory and copies the log afterward. It did not require broader application permissions.

## Remaining platform differences

This is comparable application work, not pixel identity or a claim that every renderer implements every Markdown extension identically.

- **Deno window chrome:** the installed host retains a 28-point native titlebar. Its two backends interpret initial window height differently, so the app measures and fits its client area before mounting the transcript. The target remains **1280×720** (or **900×720** for narrow QA); Deno's outer window is taller. Its current first-window behavior is consistent with the documented adoption/creation distinction and the [upstream chrome issue](https://github.com/denoland/deno/issues/35635). See [Deno's window API](https://docs.deno.com/runtime/desktop/windows/).
- **GPUI inline code:** GPUI 0.2.2 text runs support a different font family but not an independent font size within a paragraph. Inline code uses Menlo at the paragraph size rather than RN's 13 points. Fenced code uses the correct 12/18 style. GPUI also uses translucent in-window controls rather than the same native glass implementation as RN.
- **Renderer details:** Flutter's stock GFM table renderer retains its cell layout and lacks a simple alternating-body-row style hook; its quote grouping and baseline layout also differ. GPUI uses separate widgets for the structured blocks. These are visible typography/decoration differences, not flattened tables or skipped Markdown work.
- Images remain disabled. These checks do not certify image-enabled behavior, editing, all interaction paths or complete GFM conformance. Sidebar catalog contents can change as new local chats are created.

The Mac was locked during the final visual checks; the existing permitted, process-targeted capture path produced actual app content. These recordings include capture overhead and are **not scored startup/memory trials**. Rerun the standard controlled benchmark before replacing any old performance table or drawing a new framework-speed conclusion.

QA-only controls: `CHAT_HISTORY_BENCHMARK_HOME` selects the isolated catalog only when a benchmark config is present; `CHAT_HISTORY_QA_WIDTH` selects the narrow window; the config can override appearance. Normal defaults remain the user's home, 1280-point width and system appearance.
