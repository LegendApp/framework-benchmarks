> Flutter/GPUI rendering has changed after the latest measured table. See [output alignment](FLUTTER_GPUI_OUTPUT_ALIGNMENT.md); affected timings await a repeated rerun.

> **Latest results:** [September 16 final chat-history and Hello World tables](../final-2026-09-16/RESULTS.md) — 10 observations per app after 2 warmups, videos, separate memory launches, and built app sizes. Earlier tables below are historical.

> **Latest measured results:** [September 15 highlighted nine-app benchmark](HIGHLIGHTED_RESULTS_2026-09-15.md) — ten observations per app after two warmups, all unlocked, with recordings and separate memory launches. Earlier tables below are historical.

> **Cross-app fairness audit:** [September 13 audit](ALL_APPS_FAIRNESS_AUDIT.md) identifies unequal document preparation, Flutter viewport ordering, and rendering/style gaps in the broader suite. These historical timings are not an equivalent-work framework ranking.

> **Previous results:** [September 12 fairness report](FAIRNESS_RESULTS.md) contains the updated eight-app table, native stages, Hello World baselines, videos, and concurrent-load limitations. The table below is historical.

# Historical chat history results — September 11, 2026

> **Latest AppKit measurements:** [Responsive width results](RESPONSIVE_LAYOUT_RESULTS.md) supersede this table’s AppKit timing row.

> **Timing correction:** The previous full-window content detector included sidebar scrollbar fading. Its first-content, jump, and switch scores are superseded for causal comparison by the transcript-region investigation in [CAUSAL_ANALYSIS.md](CAUSAL_ANALYSIS.md). In particular, the 905 ms AppKit versus 427 ms RN startup comparison is misleading. Window and separately sampled memory figures are not changed by this detector correction.


AppKit and SwiftUI now use the same selective C++ parser and lazy document model as React Native. This run measures all eight requested apps; Tauri was excluded at the user’s request.

Apple M4, arm64, macOS 26.6.1. Two discarded warm-up rounds and ten measured iterations per app, in rotating order. Times below are video-derived p50 milliseconds. Memory is settled aggregate physical footprint in MiB, sampled in separate unrecorded launches. All 80 measured observations completed on their first attempt. The desktop was unlocked partway through: 20 timing launches began locked and 60 began unlocked. The main table combines all ten iterations per app; stratified results are provided below.

| App | Window | First content | Jump to top | Switch | Initial MiB | Top MiB | Switched MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 242.3 | 904.9 | 157.1 | 598.1 | 41.7 | 41.9 | 48.1 | 2.6 |
| SwiftUI | 295.0 | 554.3 | 287.1 | 457.5 | 49.0 | 51.5 | 55.4 | 2.9 |
| React Native | 265.7 | 426.5 | 41.1 | 155.8 | 52.4 | 57.6 | 66.7 | 27.3 |
| GPUI | 236.4 | 462.0 | 52.0 | 132.8 | 311.4 | 311.4 | 308.5 | 9.1 |
| Electron | 620.8 | 1134.6 | 55.0 | 300.1 | 505.7 | 519.6 | 285.5 | 286.1 |
| Flutter | 296.7 | 1018.6 | 64.0 | 512.8 | 89.0 | 95.0 | 115.5 | 42.5 |
| Deno CEF | 661.2 | 1244.5 | 54.5 | 328.8 | 372.5 | 385.6 | 626.1 | 307.7 |
| Deno WebView | 327.5 | 985.3 | 69.5 | 384.0 | 492.1 | 496.5 | 665.3 | 65.8 |

[Full p50/p90 report](results/2026-09-11T13-40-23.345Z.md) · [Raw results](results/2026-09-11T13-40-23.345Z.json) · [Observation journal](results/2026-09-11T13-40-23.345Z.observations.jsonl) · [80 videos and frame evidence](results/2026-09-11T13-40-23.345Z-videos/)

## Native document stages

These are p50 diagnostic timings in milliseconds, not additional intervals to add to first-content time. Native includes source access, scanning, parsing, and metadata construction. Post-native includes bridge transfer and viewport layout until app-declared readiness, which can precede the settled video frame.

| App | Initial native | Initial post-native | Switch native | Switch post-native |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 43.4 | 19.8 | 27.8 | 432.3 |
| SwiftUI | 29.3 | 159.0 | 20.9 | 409.4 |
| React Native | 42.0 | 33.9 | 25.4 | 56.0 |
| GPUI | 115.3 | 50.5 | 84.4 | 51.9 |
| Electron | 415.8 | 37.4 | 238.6 | 37.1 |
| Flutter | 695.4 | 30.0 | 453.2 | 38.1 |
| Deno CEF | 383.3 | 41.6 | 254.5 | 48.5 |
| Deno WebView | 375.3 | 64.2 | 257.8 | 87.2 |

## Session-state breakdown

P50 milliseconds, grouped by the timing launch’s starting lock state. Counts differ because the session changed during a rotating round.

| App | Locked n | Locked first | Locked switch | Unlocked n | Unlocked first | Unlocked switch |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 2 | 894.1 | 705.2 | 8 | 910.3 | 591.7 |
| SwiftUI | 2 | 587.0 | 485.4 | 8 | 551.6 | 454.4 |
| React Native | 2 | 385.9 | 155.5 | 8 | 430.0 | 155.8 |
| GPUI | 2 | 452.9 | 148.7 | 8 | 465.8 | 132.8 |
| Electron | 3 | 1011.0 | 299.6 | 7 | 1210.9 | 300.6 |
| Flutter | 3 | 1019.3 | 758.7 | 7 | 1017.9 | 510.6 |
| Deno CEF | 3 | 1461.5 | 332.1 | 7 | 1234.5 | 328.8 |
| Deno WebView | 3 | 969.5 | 402.6 | 7 | 1001.1 | 379.3 |

## Tauri: historical reference only

Tauri was not rerun. Its September 6 values below used earlier fixture bytes and an earlier harness, so they are not a matched row in the new comparison and do not establish that its performance is unchanged.

| App | Window | First content | Jump to top | Switch | Initial MiB | Top MiB | Switched MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Tauri (historical) | 286.9 | 607.5 | 67.6 | 184.5 | 390.0 | 390.2 | 422.4 | 11.3 |

[Historical Tauri report](results/2026-09-06T10-36-23.586Z.md)

## Interpretation and validation

- This run explicitly allowed a locked console session, as requested. Every raw timing observation records its starting lock state. The desktop was unlocked partway through (20 locked starts, 60 unlocked starts). This is a mixed-session table, not a controlled locked-versus-unlocked experiment. The smaller stratified groups below are descriptive; order and cache effects prevent attributing differences to lock state alone. Companion memory-launch lock states were not retained separately in this run.
- Tauri previously stopped executing JavaScript in an unrecorded locked-session run. Temporary tracing showed a hidden page whose heartbeat stopped, while native threads were idle. The issue also reproduced without memory sampling. That evidence does not establish the same failure in other frameworks.
- The same two history IDs were retained, but their bytes had changed since the historical benchmark. No end-to-end speedup against the old report is claimed. Every app in this run used the refreshed, hash-verified corpus.
- All 80 observations agree on the initial digest `3a290b9eb53fa834` and switched digest `c27e9dc5a848d7f6`. Images are disabled. Startup includes native catalog discovery and path resolution.
- The Swift package’s 13 tests passed, including lazy decoding, retained-row lifetime, serialization, errors, and full-corpus parity against the Swift reference parser. The core is pinned to the sibling repository revision recorded in [PROVENANCE.json](../../packages/chat-history-swift/Sources/ChatHistoryNative/PROVENANCE.json).
- AppKit and SwiftUI keep their existing UI implementations; the optimization changes their document-loading architecture. Shared parsing removes that architectural mismatch with React Native, but does not make list layout, text rendering, startup, or window presentation identical.
- The shared web renderer also resets transcript-local readiness state on each open. The React Native build required repairing its existing generated Markdown event-emitter patch; this is recorded in the dirty build provenance.
- App surfaces are captured at a requested 60 fps. Each visual boundary requires three matching frames. The report retains internal readiness separately, and each measured video has frame-selection evidence. Physical footprint includes attributable helper processes; RSS remains a secondary diagnostic in the raw report.
