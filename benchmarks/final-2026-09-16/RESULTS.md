> **Subsequent rendering change:** Flutter and GPUI list density and related layout now match RN more closely. Their rows below describe the pre-change builds; see the [output alignment and verification](../chat-history/FLUTTER_GPUI_OUTPUT_ALIGNMENT.md). No replacement repeated timing run has been published.

# Final desktop application benchmarks — September 16, 2026

Apple M4 (10 cores), arm64, macOS 26.6.1. Two discarded warmup rounds and ten measured rounds per app, rotating launch order. Fresh processes with warm filesystem caches. Timing comes from screen recordings; physical footprint comes from separate unrecorded launches.

Times below are median milliseconds. Memory and uncompressed built app bundles are MiB (1,048,576 bytes). Bundle sizes exclude symlink duplicates and do not include OS-provided frameworks. These are application-stack comparisons under the [fairness standard](../chat-history/FAIRNESS_STANDARD.md), not isolated framework-overhead measurements.

## Chat history

| App | Window ms | First content ms | Jump ms | Switch ms | Initial MiB | Top MiB | Switched MiB | App size MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 276.4 | 375.9 | 70.4 | 98.8 | 41.9 | 48.6 | 48.5 | 4.6 |
| GPUI | 257.2 | 426.6 | 50.8 | 194.8 | 303.6 | 305.4 | 323.9 | 10.8 |
| React Native | 276.5 | 442.7 | 41.7 | 166.6 | 52.3 | 57.0 | 66.2 | 42.1 |
| Tauri | 334.4 | 651.2 | 65.5 | 222.4 | 363.8 | 370.7 | 395.4 | 11.6 |
| SwiftUI | 326.7 | 742.9 | 66.0 | 549.7 | 82.5 | 83.3 | 93.0 | 5.1 |
| Flutter | 259.7 | 1126.3 | 80.4 | 633.0 | 329.8 | 341.5 | 264.6 | 48.0 |
| Deno WebView | 309.7 | 1326.6 | 76.2 | 666.0 | 407.7 | 415.7 | 582.7 | 65.9 |
| Electron | 309.8 | 1342.5 | 70.6 | 686.6 | 476.1 | 475.3 | 444.2 | 286.2 |
| Deno CEF | 326.8 | 1385.0 | 70.3 | 670.4 | 614.7 | 617.8 | 578.0 | 307.8 |

## Hello World

Minimal centered text apps, including standalone React Native and the separate app hosted by the Legend Shell. No transcript parsing, Markdown, or history list.

| App | Window ms | First content ms | Memory MiB | App size MiB |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 225.8 | 225.8 | 15.4 | 0.1 |
| SwiftUI | 226.9 | 243.0 | 18.3 | 0.1 |
| GPUI | 259.7 | 268.0 | 70.7 | 5.3 |
| Legend Shell (RN) | 259.2 | 275.8 | 23.9 | 9.3 |
| Flutter | 276.1 | 276.3 | 55.1 | 33.6 |
| React Native | 259.1 | 284.3 | 23.5 | 16.3 |
| Electron | 359.1 | 409.4 | 83.5 | 285.1 |
| Deno CEF | 359.9 | 426.8 | 202.7 | 307.0 |
| Tauri | 417.6 | 434.1 | 73.1 | 10.3 |
| Deno WebView | 409.7 | 440.3 | 83.0 | 65.0 |

## Timing spread

p90 of ten completed observations; milliseconds.

| Workload | App | Window p90 | First content p90 | Jump p90 | Switch p90 |
| --- | --- | ---: | ---: | ---: | ---: |
| Chat history | React Native | 283.7 | 443.4 | 43.4 | 168.2 |
| Chat history | Electron | 325.7 | 1374.2 | 71.1 | 687.4 |
| Chat history | Tauri | 343.5 | 693.3 | 74.9 | 232.6 |
| Chat history | Deno WebView | 325.9 | 1353.7 | 82.9 | 671.8 |
| Chat history | Deno CEF | 342.2 | 1410.2 | 72.0 | 686.3 |
| Chat history | Flutter | 293.4 | 1143.1 | 96.8 | 637.2 |
| Chat history | GPUI | 269.8 | 459.7 | 51.4 | 200.1 |
| Chat history | SwiftUI | 343.0 | 759.7 | 68.3 | 556.4 |
| Chat history | AppKit | 292.6 | 393.6 | 80.7 | 107.5 |
| Hello World | React Native | 276.1 | 292.7 | — | — |
| Hello World | Legend Shell (RN) | 259.9 | 276.6 | — | — |
| Hello World | Electron | 359.8 | 410.3 | — | — |
| Hello World | Tauri | 459.6 | 476.3 | — | — |
| Hello World | Deno WebView | 459.4 | 476.1 | — | — |
| Hello World | Deno CEF | 376.8 | 459.6 | — | — |
| Hello World | Flutter | 276.6 | 293.2 | — | — |
| Hello World | GPUI | 276.6 | 293.0 | — | — |
| Hello World | SwiftUI | 260.0 | 277.2 | — | — |
| Hello World | AppKit | 226.5 | 226.5 | — | — |

## Settled idle CPU

Separate preflight: ten seconds to settle, then twenty seconds measured using process CPU-time deltas. Percentages are of one CPU core, include attributable helpers, and exclude WindowServer. Rounded zero means below the sampling resolution.

| App | Chat history CPU % | Hello World CPU % |
| --- | ---: | ---: |
| React Native | 0.10 | 0.00 |
| Legend Shell (RN) | — | 0.00 |
| AppKit | 0.00 | 0.00 |
| SwiftUI | 0.00 | 0.00 |
| Electron | 0.69 | 0.05 |
| Tauri | 0.20 | 0.05 |
| Deno WebView | 0.55 | 0.05 |
| Deno CEF | 2.28 | 1.53 |
| GPUI | 0.35 | 0.35 |
| Flutter | 0.45 | 0.00 |

## Evidence

- [Chat raw results](../chat-history/results/2026-09-16T20-35-45.623Z.json) and [generated detail](../chat-history/results/2026-09-16T20-35-45.623Z.md).
- [Hello World raw results](../hello-world/results/2026-09-16T21-25-32.060Z/results.json) and [generated detail](../hello-world/results/2026-09-16T21-25-32.060Z/results.md).
- [Chat video viewer](../chat-history/results/2026-09-16T20-35-45.623Z-videos/index.html).
- [Hello World video viewer](../hello-world/results/2026-09-16T21-25-32.060Z/videos.html).
- [Validation](validation.json), [builds before](builds-before.json), [builds after](builds-after.json), [host CPU and thermal samples](host-monitor.jsonl), [idle CPU samples](idle-cpu.jsonl).

## Interpretation and limitations

AppKit has the lowest median first-content time and memory in both workloads. In chat history, React Native reaches first content in 442.7 ms versus GPUI's 426.6 ms and SwiftUI's 742.9 ms. RN's 16.1 ms gap behind GPUI is approximately one 60 Hz frame; do not portray it as a large or universal difference. RN uses 52.3 MiB initially versus GPUI's 303.6 MiB and SwiftUI's 82.5 MiB. AppKit uses 41.9 MiB and reaches content in 375.9 ms. RN has the lowest median jump-to-top time in this run.

- All 90 chat observations match the pinned initial and switched transcript digests. All 100 Hello World observations recognize the greeting. Both timing and memory launch records show an unlocked console.
- All 190 videos decode, with recorded frame timestamps aligned within 0.001 ms. Deno WebView Hello World iterations 5 and 6 each have one unencoded trailing capture timestamp, after the measured startup and reference frame. Every measured frame is present and aligned; no timing correction was required.
- Three chat timing attempts were discarded because the detector could not establish stable switched content: Tauri round 2, Electron round 5, Deno CEF round 6. Their replacement attempts passed. No Hello World attempts were discarded. These are completed-launch performance distributions; retries remain available in the raw data/run logs.
- Whole-bundle file-content manifests are identical before and after measurement. The snapshot also includes an unused older RN Optimized bundle; it is not a row in either suite. Release build inputs and dirty working-tree state are preserved in the build manifests. RN/web share Legend List `3.3.10-sparse-layout.a6f5ba13`.
- Host CPU was sampled every five seconds. During measured chat collection, whole-host busy CPU was median 7.2%, p90 14.0%, maximum 25.9%; Hello World was median 9.4%, p90 17.1%, maximum 29.7%. This includes the app, recording, OCR/video processing, and background processes; it is not background-only CPU. Every sampled thermal state was nominal. A Spotlight indexing burst occurred during chat warmups and ended before measured collection. This is a monitored desktop session, not a laboratory-isolated machine.
- Idle CPU preflight found no major busy loop. Deno CEF was highest at 2.28% of one core for chat and 1.53% for Hello World. These CPU values are a separate short settled-idle sample, not startup CPU measurements.
- Visual inspection covers iteration 1 of every app at initial, top, and switched chat states, plus each Hello World window. See [initial](visual/initial-contact.png), [top](visual/top-contact.png), [switched](visual/switch-contact.png), and [Hello World](visual/hello-contact.png) contact sheets. All show the expected content. They are not pixel-identical: Flutter/GPUI use looser list spacing, native text metrics and header spacing differ, and window chrome varies. This affects visible item density and limits any claim of identical rendering work.
- Markdown, highlighting, text layout, and list caching use each platform's chosen libraries. Flutter retains its list's two-viewport cache floor; native lists retain native preparation policies. These are disclosed stack properties, not proof that one framework is intrinsically faster. No universal Markdown-extension parity is claimed.
- Startup is fresh-process, warm-filesystem startup with process-local automatic window animations disabled by the harness. It is not cold-boot or first-install startup. The chat fixtures and live catalog conditions belong to this session. The two suites use workload-appropriate detectors: settled transcript matching for chat and greeting OCR for Hello World.
- Physical footprint aggregates attributable app/helper processes. WebKit helpers are attributed relative to each launch's baseline, so unrelated simultaneous WebKit work would be a limitation. OS frameworks and WindowServer are not charged to individual app bundle sizes or footprints. Bundles are uncompressed on-disk build contents, not installer/download sizes; packaging differs across stacks.
- Both complete release builds succeeded. Fairness/detector tests passed (9 tests, 26 assertions), and TypeScript checking passed. No application tuning was performed during collection.

The September 15 table is historical and predates the final shared-list alignment. Use this September 16 run for these frozen builds; do not attribute cross-run differences solely to framework changes.
