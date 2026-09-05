# Chat History Framework Benchmark

This benchmark compares React Native macOS, Electron, Tauri, Deno Desktop
WebView, Deno Desktop CEF, Flutter, GPUI, SwiftUI, and AppKit. React Native is
maintained in the sibling `legend-apps` repository and exported into this
repository's common production-build directory for every default run.

## What is measured

Every implementation must expose the same phase boundaries:

1. `loadMs`: open and read the selected Codex or Claude JSONL file in the host.
2. `scanMs`: split the source into records.
3. `parseMs`: parse provider records and normalize display rows.
4. `nativeTotalMs`: total host work before returning across a bridge.
5. `bridgeRoundTripMs`: renderer-observed request-to-response time. Native-only
   implementations report `0` because their model is already in-process.
6. `firstPaintMs`: time from selection until the first committed transcript
   paint.

The result UI also reports source bytes, record count, display row count, and
warning count. Measurements must come from release builds on the same machine.

## Production benchmark suite

The automated suite records these end-to-end metrics from every app.
User-visible timing comes from an
external ScreenCaptureKit recording rather than each framework's readiness
callback:

1. LaunchServices launch to the first recorded frame containing the app window;
2. launch to the first of three stable frames matching the settled initial
   transcript viewport;
3. selection start to the first of three stable frames matching the settled
   switched transcript viewport;
4. stabilized aggregate RSS and macOS physical footprint of the app process
   and descendants after initial readiness;
5. stabilized RSS and physical footprint after the switch; and
6. logical bytes in the production `.app` bundle.

Every app is launched as a new, activated `.app` instance through
`NSWorkspace.OpenConfiguration`, with the same environment and pinned corpus.
A stable-bundle-ID capture helper records the target process's compositor
surfaces at a requested 60 fps, even when automation places its window on a
non-frontmost Space. The helper stores each WindowServer presentation timestamp.
The harness retains app-declared readiness and parser stages as diagnostics, but
they do not determine the visual result. A cropped MP4 and JSON frame-selection
sidecar are saved for every measured iteration so every timing is auditable.

The settled reference is sampled after the app's diagnostic readiness boundary
and before the automated switch (or after switched-content settlement). The
harness searches backward for the first three consecutive matching frames.
Window opening is detected independently by comparing the future window region
with its pre-launch pixels. This measures a usable virtualized viewport, not
construction of every offscreen row.

Images are disabled for the standard corpus so network availability and local
attachment decoding do not contaminate renderer comparisons. Fixture hashing
reads every byte before measurement to establish a controlled warm filesystem
cache. The runner keeps transcript paths and metadata in its private fixture
manifest, but gives each app only the two pinned provider/id pairs. Every app
must scan the native Codex and Claude stores, resolve those IDs to paths, and
construct its sidebar catalog after process launch; that discovery is included
in first-content time. Every run starts a new production process. Two warm-up rounds are
discarded and ten measured rounds rotate app order deterministically, giving
every app equal exposure to each position. Reports include p50 and p90 timing,
all raw observations, and native-versus-post-native stage diagnostics. Memory
is the median of three samples after a 300 ms settlement period.
Tauri and Deno WebView memory also includes the WebKit GPU, networking, and
content XPC helpers created by its iteration; macOS reparents those helpers to
`launchd`, so they do not appear in the normal process-descendant tree.

Every measured content selection also emits a canonical 64-bit FNV-1a digest
of the normalized display rows. Apps report visual readiness first, then
compute the digest outside the measured path. The digest covers row kind,
Markdown, tool label, preview and status, image state and sources, and file
paths and line counts; each UTF-8 field is length-prefixed. The runner aborts
before writing a report if any implementation or iteration produces a
different initial or switched digest. This prevents fast but incomplete
parsers from entering the table without making validation part of the timing.

### Pin stable fixtures

The selector chooses the two largest non-subagent histories whose final record
is at least eight days old. It writes an ignored local manifest containing the
paths, activity times, byte sizes, and SHA-256 hashes:

```sh
bun run benchmark:fixtures
```

The runner verifies size and hash before launching an app and aborts if either
fixture changed. On the current benchmark machine the pinned pair is:

- `Diagnose LegendList overlap` — 228.25 MiB, last active August 20, 2026;
- `Audit app performance issues` — 140.99 MiB, last active August 18, 2026.

Both are Codex histories because this machine currently has no `~/.claude`
history store. Claude remains covered by parser conformance fixtures, but a real
Claude performance corpus requires importing and pinning a stable Claude file.

### Build and run

Build all production-mode `.app` bundles, including React Native from
`legend-apps`:

```sh
bun run benchmark:build
```

The build uses a `main` checkout at `../legend-apps`, or discovers the
repository's `main` worktree when the sibling checkout is on another branch.
It falls back to the sibling only when no usable `main` worktree exists. An
explicit path always wins:

```sh
LEGEND_APPS_REPO=/absolute/path/to/legend-apps bun run benchmark:build
bun run benchmark:build --react-native-repo /absolute/path/to/legend-apps
```

React Native is built in Xcode's Release configuration and copied into the
common build directory with an ad-hoc signature. This is production-mode code,
but intentionally skips distribution signing and notarization so every
framework is measured under the same local conditions. The build manifest
records both repository commits and whether either checkout was dirty.

Run two discarded warm-up rounds and ten measured iterations per app:

```sh
bun run benchmark:run
```

Useful focused runs:

```sh
bun benchmarks/chat-history/run.ts --app electron --warmups 0 --iterations 1
bun benchmarks/chat-history/run.ts --app react-native --warmups 0 --iterations 1
bun benchmarks/chat-history/run.ts --app all --warmups 2 --iterations 10
```

Video recording is the default and requires `ffmpeg`, `ffprobe`, and macOS
Screen Recording access for `Chat History Benchmark Capture`. Use
`--no-video` only for internal-event diagnostics; those timings are explicitly
marked non-visual and are not comparable with the final reports.

Machine-readable JSON, a Markdown summary, cropped videos, and frame sidecars
are written under the ignored `benchmarks/chat-history/results/` directory. Run
the full build and benchmark in one command with
`bun run benchmark`.

## Modes

### End-to-end

Each framework uses its idiomatic host implementation:

- React Native macOS: C++ parser behind a Nitro hybrid object, with the
  production React Native renderer and LegendList virtualization.
- Electron: Node filesystem and parser in a persistent worker thread, copied
  over isolated IPC without blocking the main process.
- Tauri: shared Rust filesystem and parser on the async runtime's blocking
  thread pool, serialized through a Tauri command.
- Deno Desktop: Deno filesystem and parser in a persistent Web Worker, encoded
  through in-process bindings into either WKWebView or CEF.
- Flutter: Dart filesystem and parser running in a background isolate, with
  normalized rows transferred back through isolate messaging.
- GPUI: Rust filesystem and parser running on GPUI's background executor, with
  normalized rows moved directly into a GPU-native variable-height list.
- SwiftUI and AppKit: memory-mapped Swift byte scanning with no whole-file
  `String` or per-line `Data` copies, parsed in the application process.

This mode measures the actual architecture a production app would use.

### Renderer-only

Each renderer receives the same normalized document fixture. This mode removes
filesystem, parser, and bridge differences so scrolling, layout, and memory can
be compared independently. It will be added after all end-to-end loaders pass
the fixture conformance tests.

## Required behavior

Both Codex and Claude inputs must produce the same visible rows as the existing
C++ implementation. Implementations must:

- select Claude's latest non-sidechain parent chain;
- pair tool calls with results and group work preceding the last tool in a turn;
- omit reasoning/thinking and application-only Codex directives;
- retain user and assistant Markdown, file-change summaries, image references,
  timestamps, and parse warnings;
- discover current Codex and Claude sessions without reading every transcript
  solely to construct the sidebar.

The small conformance fixtures live in
`packages/chat-history/tests/fixtures`. Large generated corpora will be kept
outside Git and described by a deterministic generator.

## Target order

1. Electron end-to-end loader, parser, IPC, and transcript shell.
2. Tauri using the same web renderer contract and a Rust backend.
3. A Swift package containing the shared Swift parser plus separate SwiftUI and
   AppKit executables.
4. Renderer-only corpus and automated launch/scroll/append traces.

## Running Electron

From the repository root:

```sh
bun install
bun run chat-history:electron
```

The renderer is bundled with production React and runs with Electron context
isolation, sandboxing, and Node integration disabled. The main process validates
every IPC sender and requested transcript path, while a persistent Node worker
thread reads and parses transcripts. The complete normalized document crosses
Electron IPC as the measured bridge payload.

The renderer supports GitHub-flavored Markdown, local images, expandable tool
and file details, restored chat selection, and an in-webview settings modal.
Electron persists settings as JSON in its native user-data directory.

## Running Tauri

The Rust toolchain is scoped to `.toolchains` in this worktree; the scripts set
`CARGO_HOME`, `RUSTUP_HOME`, and `PATH` without modifying shell startup files.

```sh
bun install
bun run chat-history:tauri
```

Tauri uses the same bundled renderer source as Electron. Session discovery,
JSONL parsing, normalization, and path validation use the shared Rust parser on
the async runtime's blocking thread pool. The normalized document is serialized
through a Tauri command into macOS WKWebView.

Tauri persists the shared settings schema through Rust, exposes scoped local
images through its asset protocol, and opens Markdown links in the system
browser. Its settings remain in the shared in-webview modal.

## Running Deno Desktop

The Deno toolchain is scoped to `.toolchains` in this worktree. Both builds use
the same Deno backend, React renderer, native file discovery, persistent parser
worker, and in-process bindings. Their packaged permissions are limited to the
provider histories, settings, benchmark files, local renderer server, and
system link opener. Only the rendering backend changes:

```sh
bun run chat-history:deno:webview
bun run chat-history:deno:cef
```

The WebView build uses macOS WKWebView. The CEF build bundles Chromium, making
the pair a controlled rendering-engine comparison without changing app code.

## Running Flutter

Flutter is installed locally under `.toolchains` and does not modify the
machine-wide SDK. The app uses a background Dart isolate for native filesystem
discovery and JSONL parsing, then renders the normalized transcript with a lazy
Flutter list:

```sh
bun run chat-history:flutter
```

It renders Markdown and local images, expands tool and file details, restores
selection, and persists its settings with `SharedPreferences`.

## Running GPUI

The Rust toolchain is scoped to `.toolchains`. GPUI uses Metal for a native GPU
renderer, a variable-height lazy list for the transcript, and the shared Rust
Codex/Claude parser:

```sh
bun run chat-history:gpui
```

The app renders Markdown blocks and local images, exposes expandable tool and
file rows, restores selection, and persists its appearance-aware settings
overlay as JSON in Application Support.

## Running SwiftUI

SwiftUI and AppKit share the native `ChatHistoryCore` Swift package for session
discovery, mapped file loading, JSONL parsing, normalization, and timing.

```sh
bun run chat-history:swiftui
```

The SwiftUI target uses a native split view and SwiftUI `List` for the
virtualized transcript. There is no serialization bridge, so bridge time is
reported as zero.

SwiftUI renders native attributed Markdown and images, exposes expandable tool
and file details, restores selection, and persists its settings sheet through
`UserDefaults`.

## Running AppKit

```sh
bun run chat-history:appkit
```

The AppKit target uses `NSSplitViewController` and reusable `NSTableView` cells
for both the session catalog and transcript. It calls the same Swift core
directly and therefore also reports zero bridge time.
