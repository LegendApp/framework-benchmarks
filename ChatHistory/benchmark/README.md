# Chat History Framework Benchmark

This benchmark compares React Native macOS, Electron, Tauri, Deno Desktop
WebView, Deno Desktop CEF, Flutter, GPUI, SwiftUI, and AppKit. React Native is
maintained in the sibling `legend-apps` repository and exported into this
repository's common production-build directory by the build command. Benchmark runs use existing builds.

For the latest chat run, see the [September 23–24 refresh of all ten frameworks](../results/results.md). Older full-suite runs remain in Git history. The earlier parser/layout checkpoint is in [Swift/native parity results](SWIFT_PARITY_RESULTS.md). The prior production comparison is in [responsive AppKit results and SwiftUI diagnosis](RESPONSIVE_LAYOUT_RESULTS.md). The earlier detector correction and causal experiments are in [CAUSAL_ANALYSIS.md](CAUSAL_ANALYSIS.md). The earlier eight-app run and memory measurements are in [RESULTS.md](RESULTS.md).
[PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md) preserves the historical
September 4 analysis and its earlier implementation/corpus.

See the [rendering-work audit](RENDERING_WORK_ALIGNMENT.md) for later source corrections and the remaining distinction between comparable features and identical rendering work.

## Fairness standard

The [fair comparison standard](FAIRNESS_STANDARD.md) defines comparable visible work with idiomatic platform engines. Build-time rendering provenance is required by the runner; shared-list or policy drift must be resolved before measuring.

## Swift document backend

AppKit and SwiftUI default to the equivalent lazy Swift parser. Their catalog discovery remains Swift/Foundation. Use `CHAT_HISTORY_PARSER=cpp` to run the same UIs with the vendored RN C++ document core; the report records the backend. See the [native implementation policy](../packages/chat-history-swift/README.md) for the standardized layout rules and remaining renderer differences.

## Minimal-project counterpart

The [Hello World suite](../../HelloWorld/benchmark/README.md) measures the same nine runtimes with a standalone minimal app. Use `bun run benchmark:hello-world:build`, then `bun run benchmark:hello-world:run`, and `bun run benchmark:compare` to combine the two reports. Hello World compares startup, settled footprint, and bundle size; transcript-specific metrics below apply to the full product only.

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
3. a non-animated jump request to the first of three stable frames matching
   the top of the initial transcript;
4. selection start to the first of three stable frames matching the settled
   switched transcript viewport;
5. stabilized aggregate macOS physical footprint of the app process and
   descendants after initial readiness;
6. stabilized physical footprint after the jump to the top;
7. stabilized physical footprint after the switch;
8. logical bytes in the production `.app` bundle.

Reports use physical footprint as the primary memory-cost metric on macOS.
Aggregate RSS is retained in a separate diagnostic table because it includes
resident shared libraries and memory mappings and can double-count shared
pages across a multiprocess app.

When video is enabled, each measured timing launch is followed by an identical
non-recording production launch whose settled memory replaces the timing
launch's memory fields. The recorded launch performs no footprint sampling;
only the companion launch invokes the memory sampler. ScreenCaptureKit can charge capture surfaces to
GPU-backed applications, so combining visual timing and memory in one process
would materially overstate some renderers' normal footprint.

By default the runner requires an unlocked console session. An explicit
`--allow-locked-session` run is supported and records the lock state with each
observation. A shareable display can belong to a locked session; Tauri was
observed suspending its hidden JavaScript page during unrecorded launches,
while recording kept that page running. That finding does not establish the
same failure in every renderer. Locked-session results describe that condition
and should not be presented as verified foreground measurements. All phase,
content-parity, and video-evidence checks still apply. Use `--launch-attempts 1`
to report the first failed launch without retrying it.

Every app is launched as a new, activated `.app` instance through
`NSWorkspace.OpenConfiguration`, with the same environment and pinned corpus.
A stable-bundle-ID capture helper records the target process's compositor
surfaces at a requested 60 fps, even when automation places its window on a
non-frontmost Space. The helper stores each WindowServer presentation timestamp.
The harness retains app-declared readiness and parser stages as diagnostics, but
they do not determine the visual result. A cropped MP4 and JSON frame-selection
sidecar are saved for every measured iteration so every timing is auditable.

Detector v4 keeps v3's transcript ROI and three-frame matching thresholds, but crops against the settled window bounds instead of an intermediate opening-animation frame. Recorded AppKit, SwiftUI, and RN runs also reject a settled window width other than 1280 points (within two points).

Each settled reference is sampled after the app's diagnostic readiness boundary
and before the next automated phase. The harness searches backward for the
first three consecutive matching frames.
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
in first-content time. Reports also show discovery separately as the app-side
wall time from starting the native catalog request until the catalog is
available back in the app. Every run starts a new production process. Two warm-up rounds are
discarded and ten measured rounds rotate app order deterministically, giving
every app equal exposure to each position. Reports include p50 and p90 timing,
all raw observations, and native-versus-post-native stage diagnostics. Only
launches that emit every required phase enter the aggregate; an incomplete
launch is discarded and retried up to twice, then fails the run. Memory is the
median of three samples beginning 2.5 seconds after the corresponding
content or viewport readiness boundary and spaced 200 ms apart. This reports
the 2–3 second settled footprint instead of transient launch or relayout
graphics allocations. The runner enforces enough time before the jump and
automatic chat switch to finish each settled-memory sample window.
Tauri and Deno WebView memory also includes the WebKit GPU, networking, and
content XPC helpers created by its iteration; macOS reparents those helpers to
`launchd`, so they do not appear in the normal process-descendant tree.

Completed observations are journaled to a per-run `.observations.jsonl` file so
partial evidence survives an interrupted run.

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

Prebuilt apps can be installed with `bun run benchmark:download --suite chat-history --repo OWNER/REPO` from the matching release checkout. See the [release instructions](../../docs/BENCHMARKS.md#prebuilt-releases) for prerequisites, version pinning, and publishing.

### Build and run

Build all production-mode `.app` bundles, including React Native from
`legend-apps`:

```sh
bun run benchmark:build --suite chat-history
```

The builder previews the selected apps and asks for confirmation before starting. Use `--yes` for automation or `--dry-run` to inspect the plan. It uses the exact sibling `../legend-apps` checkout by default, with no implicit worktree selection. Override the path explicitly:

```sh
bun run benchmark:build --suite chat-history --legend-apps-repo /absolute/path/to/legend-apps
```

See the [root command reference](../../docs/BENCHMARKS.md#arguments-and-defaults) for all supported arguments. Without `--suite`, the root build/run commands select both workloads.

React Native is built in Xcode's Release configuration and copied into the
common build directory with an ad-hoc signature. This is production-mode code,
but intentionally skips distribution signing and notarization so every
framework is measured under the same local conditions. The build manifest
records both repository commits and whether either checkout was dirty.

Run two discarded warm-up rounds and ten measured iterations per app:

```sh
bun run benchmark:run --suite chat-history
```

Useful focused runs:

```sh
bun ChatHistory/benchmark/run.ts --app electron --warmups 0 --iterations 1
bun ChatHistory/benchmark/run.ts --app react-native --warmups 0 --iterations 1
bun ChatHistory/benchmark/run.ts --app all --warmups 2 --iterations 10
bun ChatHistory/benchmark/run.ts --app appkit,swiftui --warmups 2 --iterations 10
```

Video recording is the default and requires `ffmpeg`, `ffprobe`, and macOS
Screen Recording access for `Chat History Benchmark Capture`. Use the low-level `bun ChatHistory/benchmark/run.ts` with
`--no-video` only for internal-event diagnostics. Those reports are explicitly
marked diagnostic-only and are not comparable with final video-derived
reports. Framework callbacks generally precede WindowServer presentation, so
adding artificial delays to make the two boundaries agree would reduce rather
than improve measurement accuracy.

Latest JSON data and a Markdown summary replace `ChatHistory/results/{summary.json,raw.json,results.md}`. Cropped videos, frame sidecars, and the observation journal are ignored under `.build/chat-history-benchmarks/runs/<timestamp>/`. Building and measuring are separate commands; `bun run benchmark` runs existing builds across both workloads.

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
- SwiftUI and AppKit: the same selective C++ parser and lazy native document
  core as React Native, exposed through an Objective-C++ ownership adapter.
  Swift row IDs and metadata are available immediately; body and preview text
  are decoded and cached on demand. The original Swift parser is retained as a
  conformance reference. See the [native core provenance and adapter notes](../packages/chat-history-swift/Sources/ChatHistoryNative/README.md).

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
discovery, a shared C++ lazy document core, row adapters, and timing.

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

Content detector v3 scores the same transcript region in every app (24–98% of window width, 14–98% of height), excluding sidebar and header animations. Evidence retains legacy full-window scores and all source frame timestamps; saved video preserves frame count. Window timing is still detected separately. Run detector regression tests with `bun test ChatHistory/benchmark/video.test.ts`.

For the measured causes of the native/RN differences, see the [platform timing investigation](PLATFORM_TIMING_REPORT.md).

Built-in TextKit update: [native renderer changes, current three-app results, and videos](TEXTKIT_RESULTS.md).

Fairness completion: [implementation changes, common presentation policy, and matched results](FAIRNESS_RESULTS.md).

The September 13 [other-app alignment report](ALL_APPS_ALIGNMENT.md) documents deferred document loading, rendering/chrome corrections, visual evidence and remaining platform differences. These changes require fresh scored benchmarks; prior performance tables describe earlier builds.

Syntax highlighting is now enabled across all nine targets. See [the highlighting policy and validation](SYNTAX_HIGHLIGHTING.md). Existing performance tables predate this change and require a complete rerun for the highlighted workload.

## Running Compose Multiplatform

Build the self-contained release with `bun run benchmark:build --suite chat-history --app compose`; run the same foreground/video and separate-memory protocol with `bun run benchmark:run --suite chat-history --app compose`. Development: `bun run chat-history:compose` after building its external syntax pack. `BENCHMARK_GRAMMAR_ROOT` can override the common grammar-pack root; otherwise development uses `.build/chat-history-benchmarks/grammar-packs/v1` relative to the working directory. Kotlin parser and syntax policy tests: `scripts/with-local-compose.sh :chat:test`.

See [Compose implementation notes](../../docs/COMPOSE_MULTIPLATFORM.md). The macOS ARM64 exports contain their own trimmed Java runtime; users do not need a separate Java install. Benchmark timings include normal JVM startup and JIT behavior.

## Comparing fixed app bundles

The lower-level chat runner can measure one retained build without replacing the normal installation:

```sh
bun ChatHistory/benchmark/run.ts --app react-native \
  --app-bundle /absolute/path/to/saved.app \
  --build-manifest /absolute/path/to/saved-build-manifest.json \
  --warmups 2 --iterations 10
```

`--app-bundle` requires exactly one selected app and its matching saved build manifest. Helpers still come from the standard build directory. The report records the selected executable path and supplied build provenance. Keep each bundle at a fixed path throughout an A/B experiment and warm up each build before scoring; replacing bundles between observations can add first-launch overhead. These diagnostic arguments belong to the lower-level runner, not the unified suite command.
