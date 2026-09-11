# Chat History Performance Analysis

This is the talk-ready interpretation of the September 4, 2026 production
benchmark. The [raw report](results/2026-09-04T18-50-07.560Z.md) and
[machine-readable observations](results/2026-09-04T18-50-07.560Z.json) remain
the source of truth.

## Executive summary

React Native produced the best overall user-visible result in this experiment:
253 ms to a window, 494 ms to stable initial content, and 135 ms to stable
switched content. GPUI was effectively tied once running, at 511 ms initial
content and 134 ms switching. AppKit was close on initial content at 536 ms,
and Tauri followed at 593 ms.

The React Native result is not evidence that JavaScript parses 228 MiB JSONL
faster than native code. This app deliberately keeps the expensive path out of
JavaScript: a memory-mapped C++ parser creates a native document exposed lazily
through a Nitro hybrid object, while LegendList asks for only the visible row
metadata. That combination avoids both a full source-file allocation and a
full normalized-document serialization across the native/JavaScript boundary.

The central lessons are:

1. Data-path architecture mattered more than the UI-language label. Tauri's
   Rust parser was the fastest initial parser, but React Native still reached
   visible content sooner because its complete startup and presentation path
   was shorter.
2. A system webview makes an application bundle small, not memory-free. Tauri
   shipped an 11 MB bundle but used a 537 MB initial physical footprint after
   the benchmark included its WebKit helper processes.
3. Native UI is not automatically fast. SwiftUI and AppKit avoided a bridge and
   had excellent memory and bundle size, but their parser and variable-height
   text/list layout paths dominated different interactions.
4. Moving work off the UI thread preserves responsiveness but does not remove
   the work. Flutter's background isolate and the JavaScript worker-based apps
   remained limited by parsing hundreds of megabytes.
5. Bundle size, launch speed, and runtime memory are separate properties. No
   framework won all three.

## What was measured

- Machine: Apple M4, arm64, macOS 26.6.1.
- Corpus: a 228.25 MiB initial Codex history and a 140.99 MiB switched history.
- Cache state: controlled warm filesystem cache; fixture bytes are read and
  hashed before measurement.
- Runs: two discarded warm-ups and ten measured production launches per app.
- Timing authority: external 60 fps ScreenCaptureKit video. Each content result
  is the first of three frames matching the settled viewport.
- Memory: median of three macOS physical-footprint samples, starting 300 ms
  after app-declared readiness. Aggregate RSS is diagnostic only.
- Correctness: every implementation produced identical normalized content
  digests for both histories.
- Images: disabled to remove network and image-decoding variance.

The large performance corpus contains Codex data. Claude parsing is covered by
conformance fixtures, but this machine had no real Claude history suitable for
the large-file benchmark.

## Results

Times are video-derived p50 values. Memory is p50 macOS physical footprint.

| App | Window | First content | Switch | Initial footprint | Switched footprint | Bundle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| React Native | **253 ms** | **494 ms** | 135 ms | 95 MB | 129 MB | 17.0 MB |
| Electron | 363 ms | 787 ms | 288 ms | 609 MB | 448 MB | 286.1 MB |
| Tauri | 302 ms | 593 ms | 161 ms | 537 MB | 550 MB | 11.3 MB |
| Deno WebView | 255 ms | 847 ms | 334 ms | 650 MB | 835 MB | 65.8 MB |
| Deno CEF | 580 ms | 827 ms | 304 ms | 714 MB | 691 MB | 307.7 MB |
| Flutter | 294 ms | 978 ms | 498 ms | 253 MB | 295 MB | 42.5 MB |
| GPUI | 261 ms | 511 ms | **134 ms** | 378 MB | 381 MB | 9.1 MB |
| SwiftUI | 410 ms | 809 ms | 446 ms | **40 MB** | 114 MB | 2.7 MB |
| AppKit | 279 ms | 536 ms | 516 ms | 87 MB | **94 MB** | **2.4 MB** |

At 60 fps, React Native and GPUI's 0.7 ms switch difference is not
distinguishable. Their window difference is also below one frame. React Native
has the best combined result; GPUI is in the same performance tier.

### Relative to React Native

| App | First content | Switch | Initial footprint |
| --- | ---: | ---: | ---: |
| React Native | 1.00× | 1.00× | 1.00× |
| Electron | 1.59× | 2.14× | 6.42× |
| Tauri | 1.20× | 1.20× | 5.67× |
| Deno WebView | 1.71× | 2.48× | 6.86× |
| Deno CEF | 1.67× | 2.26× | 7.53× |
| Flutter | 1.98× | 3.70× | 2.67× |
| GPUI | 1.03× | 0.99× | 3.99× |
| SwiftUI | 1.64× | 3.31× | 0.42× |
| AppKit | 1.08× | 3.83× | 0.92× |

These factors describe these implementations and this large-file workload;
they are not universal framework multipliers.

## Where the time went

The following p50 diagnostics are app-declared stages. They help attribute the
video result but are not substitutes for video timing. “Native” means host file
loading, scanning, and parsing. “Post-native” includes bridge transfer when one
exists and the framework's visible-viewport layout.

| App | Initial native | Initial post-native | Switch native | Switch post-native |
| --- | ---: | ---: | ---: | ---: |
| React Native | 120 ms | 82 ms | 36 ms | 70 ms |
| Electron | 385 ms | 75 ms | 225 ms | 73 ms |
| Tauri | **92 ms** | 68 ms | 71 ms | 68 ms |
| Deno WebView | 377 ms | 67 ms | 241 ms | 71 ms |
| Deno CEF | 410 ms | 75 ms | 239 ms | 74 ms |
| Flutter | 716 ms | **25 ms** | 445 ms | **34 ms** |
| GPUI | 109 ms | 55 ms | 84 ms | 52 ms |
| SwiftUI | 276 ms | 333 ms | 178 ms | 236 ms |
| AppKit | 288 ms | 17 ms | 191 ms | 238 ms |

The stages do not add directly to launch-to-content because each app also pays
for process startup, runtime initialization, window creation, scheduling, and
WindowServer presentation. Internal callbacks can precede or follow the first
stable captured frame. Video remains the user-visible timing authority.

### Follow-up: why Tauri won the measured initial parser stage

Tauri's 92 ms initial native stage versus React Native's 120 ms was specific to
the larger fixture, not a general Rust-versus-C++ result. React Native was
already much faster on the switched fixture: 36 ms versus Tauri's 71 ms.

The 228 MiB initial file has 8,259 records, including 42 individual lines larger
than 1 MiB and a maximum line of 8.27 MB. Approximately 135 MiB is
`custom_tool_call_output`; 98.5 MiB of that is in 26 image-rich records larger
than 1 MiB. The switched file has 10,401 records but no line larger than 1 MiB.

Rust's `serde_json` parses each complete line once and then performs keyed
lookups. The custom C++ reader is normally more selective, but its generic
member lookup walked an entire large `output` array merely to determine the
value's end, even though the UI intentionally omits array-form image output.
That unnecessary traversal explains both the Tauri initial win and React
Native's much stronger result on the smaller-line fixture.

A follow-up fix added a value-kind probe that recognizes an array from its
first byte and avoids traversing an output the app will omit. In ten
interleaved warm-cache native-parser runs against the exact benchmark files:

| Fixture | C++ baseline | C++ kind-probe | Change |
| --- | ---: | ---: | ---: |
| 228 MiB initial | 88.4 ms | 24.0 ms | **73% faster** |
| 141 MiB switched | 20.5 ms | 15.9 ms | **22% faster** |

The optimized probes produced the same authoritative content digests
(`ca557af93521760f` and `21cb21d30fa314c6`), passed the native parser suite
under normal, Release, AddressSanitizer, and UndefinedBehaviorSanitizer builds,
and passed the production macOS app verification.

The production app was then rebuilt and measured with the same two warm-ups,
ten recorded iterations, and fixed fixtures. A contemporaneous Release A/B
changed only the parser source:

| React Native metric | Baseline | Kind-probe | Change |
| --- | ---: | ---: | ---: |
| Initial native stage | 121.8 ms | 34.5 ms | **72% faster** |
| App-declared first-content readiness | 404.8 ms | 347.5 ms | **14% faster** |
| Video-derived first content | 485.9 ms | 486.9 ms | No measurable median change |
| Video-derived first-content p90 | 513.5 ms | 505.0 ms | 8.5 ms faster |
| Switched native stage | 39.1 ms | 32.5 ms | **17% faster** |
| Video-derived switch content | 128.0 ms | 121.0 ms | 7.0 ms faster |

At the parser boundary, this reverses the original result: the patched React
Native app's 34.5 ms initial native stage is about 2.7 times faster than
Tauri's 92 ms stage on the same fixed fixture. That comparison isolates the
specific workload; it is not a general C++-versus-Rust claim.

This is a real parser and internal-readiness win, but it is not evidence of a
meaningful median visual-startup win. Once parsing became faster, the remaining
React scheduling, variable-height list measurement, and WindowServer
presentation dominated the first stable viewport. At 60 fps, the 1 ms median
first-content difference is measurement noise; the 8.5 ms p90 change is also
less than one frame. The main cross-platform table remains the original
single-session comparison so that its rows stay directly comparable. The
follow-up optimized report is
[`2026-09-05T09-29-14.411Z`](results/2026-09-05T09-29-14.411Z.md), and its
contemporaneous parser-baseline report is
[`2026-09-05T09-32-54.815Z`](results/2026-09-05T09-32-54.815Z.md).

## Why each implementation landed where it did

### React Native

**Why it was fast.** In the original cross-platform run, the 120 ms initial and
36 ms switched native stages came from the selective C++ parser, which
memory-maps the transcript and scans byte ranges without first creating a 228
MiB JavaScript string. The returned
`ChatDocument` stays native; JavaScript accesses row metadata lazily through a
Nitro hybrid object. LegendList starts at the tail with a known initial viewport
and recycles only the visible variable-height rows. Hermes bytecode, inline
requires, and deferred nonessential startup work keep the shell relatively
short.

**Why memory stayed low.** The app is a single measured process, does not ship a
browser engine, does not make a private whole-file source copy, and does not
materialize every row in JavaScript. Its footprint grew from 95 MB to 129 MB
after switching, consistent with retained renderer/list caches and allocator
high-water behavior, but the benchmark does not contain an allocation profile
that can assign that 34 MB growth precisely.

**Why the bundle was 17 MB.** The bundle contains the app executable, JavaScript
resources, React Native support, and a roughly 3 MB Hermes framework. It is
larger than the pure Swift and GPUI apps but far smaller than runtimes that ship
Chromium.

### Electron

**Why it was slower.** Its persistent Node worker reads the complete file into
a `Buffer`, scans ranges, decodes individual lines, parses them in JavaScript,
and sends the normalized document through isolated Electron IPC. The measured
385 ms initial and 225 ms switched host stages dominate; the React/LegendList
viewport adds only about 75 ms. Electron is therefore not mainly losing in DOM
list rendering in this workload—it is losing in the large-file worker/parser
and startup path.

**Why memory was high.** Four measured processes cover the Electron browser,
renderer, worker/helper, and GPU-style process architecture. Chromium/V8/Node,
the full input `Buffer`, parsed objects, IPC serialization, and renderer-side
objects all contribute. The footprint fell from 609 MB to 448 MB when switching
to the smaller fixture, evidence that fixture size and reclamation matter; the
benchmark cannot attribute the decrease to one collector or process.

**Why the bundle was 286 MB.** About 284 MB is the Electron framework. The
application's own packaged resources are only about 2 MB. This is the clearest
example of runtime distribution cost dominating application code size.

### Tauri

**Why it was fast.** Rust performed the fastest initial native stage at 92 ms.
The shared parser reads the source into a Rust byte vector/string and produces
the normalized model on a blocking thread pool. Tauri then serializes that
model through a command into WKWebView, where the shared React/LegendList
renderer needs about 68 ms. WebKit/process startup keeps total first content at
593 ms even though parsing itself beats React Native.

**Why memory was much larger than the bundle suggests.** The measurement
includes the app plus the WebKit content, networking, and GPU XPC helpers that
macOS reparents outside the ordinary child-process tree. The Rust parser also
allocates the complete input file, and the normalized model exists across a
serialization boundary. Those source-confirmed mechanisms explain why a tiny
bundle can still have a 537 MB footprint, although a category-level allocation
profile would be required to divide the total precisely.

**Why the bundle was 11 MB.** Tauri ships the Rust application and web assets
but uses the operating system's WebKit instead of embedding a browser engine.
The runtime is absent from the app bundle, not absent from runtime memory.

### Deno WebView

**Why it opened a window quickly but content arrived late.** The WKWebView shell
appeared in 255 ms, essentially tied with React Native, but the Deno worker uses
the same JavaScript whole-buffer parser as Electron. Its 377 ms initial and 241
ms switched parsing stages, plus Deno runtime, local server/binding, worker, and
webview coordination, moved stable content to 847 ms and 334 ms respectively.

**Why memory was high and grew.** Four measured processes include Deno and the
WebKit helpers. The worker source buffer, structured-cloned normalized model,
renderer objects, and WebKit processes coexist in the architecture. Footprint
rose from 650 MB to 835 MB after the second document. That growth is measured,
but whether it is retained worker data, WebKit caches, allocator high-water, or
a combination requires a dedicated allocation/category profile.

**Why the bundle was 66 MB.** The packaged executable is approximately the
entire bundle; WebKit comes from macOS. This sits between Tauri's compact Rust
host and the Chromium-bundled variants.

### Deno CEF

**Why it was slower and less predictable at launch.** It uses the same Deno
backend, worker, parser, and React renderer as Deno WebView, so their parser and
switch results are close. Replacing WKWebView with bundled CEF changed window
opening from 255 ms to 580 ms. First-content p90 reached 1,144 ms versus an 827
ms median, a 38% tail, while most apps were within roughly 0–5%. CEF process and
surface startup is therefore the observed source of this variant's launch
penalty and variance.

**Why memory and bundle size were high.** Six measured processes and the
Chromium renderer architecture produced a 714 MB initial footprint. The 308 MB
bundle includes about 238 MB of Chromium Embedded Framework plus the roughly
67 MB Deno host.

### Flutter

**Why content was slow.** Flutter created a window in 294 ms and laid out its
lazy `ListView.builder` viewport in only 25–34 ms. The bottleneck was the Dart
loader/parser in a background isolate: 716 ms for the initial file and 445 ms
for the switched file. The isolate keeps that work off the UI thread but cannot
make the byte scanning, JSON decoding, object construction, or result transfer
free. This result should be described as a parser-dominated Flutter
implementation, not a slow Flutter renderer.

**Why memory was moderate.** One measured process contains the Flutter engine,
Dart heaps/isolate, Skia rendering state, a full input byte buffer, and the
normalized document. Its 253–295 MB footprint was much lower than the browser
stacks but higher than React Native and the Swift apps.

**Why the bundle was 43 MB.** Approximately 30 MB is `FlutterMacOS.framework`
and 13 MB is the compiled application framework.

### GPUI

**Why it tied React Native.** The shared Rust parser completed the initial
native stage in 109 ms, while GPUI moved the model directly into an in-process,
GPU-native variable-height lazy list in about 55 ms. There is no serialization
bridge or browser runtime. Its 134 ms switch and React Native's 135 ms switch
are indistinguishable at the capture rate. Its initial video timing includes a
161 ms gap after GPUI's internal content callback, while its switch callback and
video agree; that pattern points to initial window/compositor presentation, not
slow steady-state list rendering.

**Why memory was unexpectedly high.** GPUI is one process but had a 378 MB
footprint. The Rust parser allocates the full 228 MiB file rather than mapping
it, and the process also owns Metal/text-rendering resources and the normalized
model. The near-flat footprint after switching is consistent with an allocator
or renderer high-water mark. This is an implementation-level explanation, not
proof that GPUI inherently requires 378 MB; category profiling would be needed
to separate source-buffer, allocator, and GPU costs.

**Why the bundle was 9 MB.** The release build is a compact native Rust
executable and resources, with no embedded browser or separately shipped UI
runtime.

### SwiftUI

**Why it was slower.** The shared Swift core memory-maps the file, but scanning
and JSON parsing still took 276 ms initially and 178 ms on switch. SwiftUI then
spent 333 ms and 236 ms in the post-native phase creating attributed Markdown,
diffing a variable-height `List`, laying out the visible tail, and performing
the programmatic bottom scroll. With no serialization bridge, this is primarily
parser plus SwiftUI view/layout work.

**Why memory and bundle size were excellent.** Clean file-backed mapped pages
do not require a private full-file copy, and AppKit/SwiftUI are supplied by
macOS. The initial footprint was only 40 MB and the bundle 2.7 MB. Footprint
rose to 114 MB after switching, likely reflecting retained text/layout caches
and allocator high-water state, but that cause is an inference rather than an
allocation-profile result.

### AppKit

**Why initial content was fast but switching was slow.** AppKit shares
SwiftUI's 288 ms initial and 191 ms switched Swift parser path. Its reusable
`NSTableView` cells needed only 17 ms of app-declared post-native work on the
initial load, helping it reach stable first content in 536 ms. On switch,
variable-height row invalidation, attributed-text creation, tail scrolling, and
synchronous table layout consumed 238 ms before the callback, followed by an
87 ms compositor-visible gap. The 516 ms switch is therefore a list/text-layout
path result, not filesystem or bridge overhead.

**Why it had the best settled memory and bundle.** It uses one process,
memory-mapped input, reusable native table cells, and system AppKit/TextKit. Its
footprint was 87 MB initially and 94 MB after switching, and its 2.4 MB bundle
was the smallest measured.

## Memory interpretation

Physical footprint is the headline metric because it better represents the
memory macOS charges to an application. RSS is not “the application's RAM use”:
it includes resident shared libraries and file mappings, excludes compressed or
nonresident pages, and can count the same shared pages once per process when
summed across a process tree.

This benchmark deliberately includes helper processes attributable to each app,
including otherwise reparented WebKit XPC helpers. That makes the comparison
closer to total app impact, but it also means process architecture matters. The
memory samples are post-load snapshots, not long-idle steady state, peak memory,
or memory-pressure tests.

One especially useful talk comparison is Tauri versus React Native: their
bundles are 11 MB and 17 MB, but their initial footprints are 537 MB and 95 MB.
Using a system runtime avoids distributing its bytes; it does not eliminate its
live processes or data copies.

## Variance and confidence

- GPUI was the most repeatable measured app: first-content and switch p90 were
  within 0.3% of p50.
- Tauri switch p90 was within 0.9% of p50.
- Every app except Deno CEF had first-content p90 within about 5% of p50.
- Deno CEF's first-content p90 was 38% above p50, so its median should be shown
  together with the tail result.
- Differences smaller than one 16.7 ms video frame should be presented as ties.

Timing attribution is high confidence where measured stages dominate (Electron,
Deno, Flutter, SwiftUI) or where source architecture removes a known boundary
(React Native, GPUI). Bundle attribution is high confidence because bundle
contents were inspected directly. Memory totals are high confidence; detailed
memory attribution is medium confidence until each app has a category-level
allocation profile under the same protocol.

## Claims that are safe for a talk

- “In this 228 MiB warm-cache workload, our optimized React Native macOS app
  reached stable content first and tied GPUI for switching.”
- “React Native won here by keeping parsing and document ownership native and
  lazy—not because JavaScript out-parsed Rust or Swift.”
- “Tauri had the fastest parser and a tiny distributable, but system WebKit and
  serialization still had runtime costs.”
- “Flutter's measured bottleneck was Dart parsing, not lazy-list paint.”
- “SwiftUI minimized initial footprint; AppKit minimized settled footprint and
  bundle size.”
- “Shipping less runtime and using less runtime memory are different goals.”

Avoid saying that one framework is universally faster, that RSS is application
memory, that system frameworks are free, or that the measured memory totals are
intrinsic minimums for their frameworks. These are canonical benchmark apps on
one machine, with one unusually large warm-cache corpus and deliberately
equivalent output.

## Reproducibility references

- Comparison repository result commit: `c85e1a0843782a069d29517750cfef8488059142`.
- React Native build commit: `ed10db81d6fdbb4dfb7898d388b0904c9182faf5`.
- Most comparison bundles were built at `224f038e405a8ea8abfa8ca5a848ce81d9519708`;
  Flutter was rebuilt at `c85e1a0843782a069d29517750cfef8488059142`
  for its sendable-isolate digest fix.
- Full methodology: [README.md](README.md).
- Every measured iteration has a cropped MP4 and frame-selection sidecar linked
  from the raw report.
