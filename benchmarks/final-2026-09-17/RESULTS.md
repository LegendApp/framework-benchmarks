# Desktop benchmark release measurements — September 17, 2026

Fresh release builds from committed source, including the latest Flutter/GPUI Markdown layout alignment. Two discarded warmup rounds and ten measured rounds per app, rotating app order. Fresh processes with warm filesystem caches. Visible timings use screen recordings; settled physical footprint uses separate unrecorded launches.

All times are median milliseconds. Memory and logical built `.app` size are MiB (1,048,576 bytes). System frameworks and symlink duplicates are excluded from bundle size. These are comparable application stacks, not a universal framework ranking.

## Chat history

| App | Window ms | First content ms | Jump ms | Switch ms | Initial MiB | Top MiB | Switched MiB | App size MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 226.9 | 318.9 | 79.1 | 88.3 | 42.4 | 49.0 | 49.0 | 4.6 |
| GPUI | 226.4 | 335.5 | 50.5 | 193.1 | 289.0 | 291.1 | 309.9 | 10.8 |
| React Native | 243.4 | 406.3 | 45.0 | 157.7 | 52.8 | 57.8 | 66.5 | 42.1 |
| Tauri | 244.0 | 544.0 | 70.6 | 218.9 | 363.5 | 370.3 | 394.1 | 11.6 |
| SwiftUI | 268.7 | 668.8 | 68.9 | 554.6 | 82.6 | 83.4 | 93.2 | 5.1 |
| Flutter | 244.3 | 1094.0 | 80.2 | 625.9 | 340.7 | 337.1 | 265.6 | 48.0 |
| Deno WebView | 419.2 | 1268.9 | 72.9 | 657.0 | 408.1 | 415.7 | 582.4 | 65.9 |
| Electron | 261.0 | 1277.7 | 70.5 | 679.0 | 477.5 | 476.2 | 445.8 | 285.7 |
| Deno CEF | 310.4 | 1294.4 | 70.5 | 670.1 | 616.9 | 618.0 | 580.8 | 307.8 |

## Hello World

| App | Window ms | First content ms | Memory MiB | App size MiB |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 193.4 | 193.4 | 15.5 | 0.1 |
| GPUI | 210.7 | 226.5 | 56.3 | 5.3 |
| Legend Shell (RN) | 218.3 | 227.5 | 23.9 | 9.3 |
| SwiftUI | 210.9 | 227.5 | 18.3 | 0.1 |
| React Native | 210.9 | 227.6 | 23.3 | 16.3 |
| Flutter | 234.4 | 259.2 | 55.0 | 33.6 |
| Electron | 277.6 | 344.5 | 83.4 | 285.1 |
| Deno CEF | 359.3 | 360.0 | 203.6 | 307.0 |
| Deno WebView | 360.9 | 394.1 | 83.0 | 65.0 |
| Tauri | 377.5 | 409.8 | 73.0 | 10.3 |

## Timing spread

p90 of ten completed observations, in milliseconds.

| Workload | App | Window p90 | First content p90 | Jump p90 | Switch p90 |
| --- | --- | ---: | ---: | ---: | ---: |
| Chat history | React Native | 244.5 | 411.2 | 47.5 | 170.0 |
| Chat history | Electron | 493.9 | 1527.2 | 71.4 | 687.0 |
| Chat history | Tauri | 261.0 | 625.6 | 83.3 | 230.5 |
| Chat history | Deno WebView | 460.3 | 1326.9 | 78.4 | 667.4 |
| Chat history | Deno CEF | 594.0 | 1710.7 | 72.1 | 688.4 |
| Chat history | Flutter | 260.3 | 1109.9 | 97.6 | 637.1 |
| Chat history | GPUI | 227.6 | 344.2 | 50.9 | 200.3 |
| Chat history | SwiftUI | 277.9 | 678.0 | 91.2 | 571.7 |
| Chat history | AppKit | 227.8 | 327.8 | 87.3 | 94.8 |
| Hello World | React Native | 226.5 | 243.1 | — | — |
| Hello World | Legend Shell (RN) | 227.4 | 244.1 | — | — |
| Hello World | Electron | 278.1 | 359.9 | — | — |
| Hello World | Tauri | 410.9 | 410.9 | — | — |
| Hello World | Deno WebView | 361.3 | 410.7 | — | — |
| Hello World | Deno CEF | 361.1 | 377.8 | — | — |
| Hello World | Flutter | 244.1 | 275.3 | — | — |
| Hello World | GPUI | 226.9 | 227.8 | — | — |
| Hello World | SwiftUI | 211.2 | 227.9 | — | — |
| Hello World | AppKit | 210.9 | 227.6 | — | — |

## Provenance and evidence

- Comparison source: `bdc0ec8fb2dedf5c3fab75bcce7227e4b46a2375`.
- React Native product/Legend Shell source: `6c31130005cc058ce78661a21a59eac0a6b98045`.
- Machine: `{"architecture": "arm64", "cpu": "Apple M4", "macOS": "26.6.1"}`.
- [Chat raw results](../../.build/release-worktrees/comparison/benchmarks/chat-history/results/2026-09-17T11-08-30.570Z.json), [Hello World raw results](../../.build/release-worktrees/comparison/benchmarks/hello-world/results/2026-09-17T11-57-30.419Z/results.json).
- [Chat videos](../../.build/release-worktrees/comparison/benchmarks/chat-history/results/2026-09-17T11-08-30.570Z-videos/index.html), [Hello World videos](../../.build/release-worktrees/comparison/benchmarks/hello-world/results/2026-09-17T11-57-30.419Z/videos.html).
- [Full evidence validation](../../.build/release-audit-2026-09-17/validation.json), [bundle hashes before](../../.build/release-audit-2026-09-17/builds-before.json), [bundle hashes after](../../.build/release-audit-2026-09-17/builds-after.json).

## Conditions and limitations

- Apple M4, arm64, macOS 26.6.1. All 19 release apps were rebuilt from clean source checkouts before packaging and measurement. No application changes occurred during the scored run.
- Ten measured observations per app after two discarded warmups. Both timing and companion memory launches passed the unlocked/on-console checks. All chat observations matched the pinned initial and switched document digests (`3a290b9eb53fa834`, `c27e9dc5a848d7f6`); Hello World OCR matched the greeting.
- All 190 measured videos passed frame-count, monotonic timestamp, encoded timestamp alignment, and measured-boundary checks. The validator allows one unencoded trailing capture timestamp for Hello World, never a measured boundary outside the encoded video. All 19 bundle tree hashes matched before and after measurement.
- One Tauri chat-history timing attempt (measured round 2) failed to detect a stable switched frame and was discarded automatically. Its retry completed successfully. No other failed attempts appear in the suite log. The tables summarize completed observations, not timeouts as successful timings.
- Quiet preflight: 13 samples, median whole-host busy CPU 5.1%, thermal state nominal. During measured collection, whole-host CPU median/p90 was 7.9%/15.6% for chat and 9.3%/14.7% for Hello World; every sample remained thermally nominal. These readings include the benchmark, capture, and analysis processes. They are not per-app idle CPU measurements; fresh idle CPU was not measured in this run.
- Reviewed first-iteration saved frames for initial content, top jump, and switched content in all nine chat apps, plus all ten Hello World apps. They display the corresponding content; native chrome, spacing, line wrapping, and font rasterization still differ. This is a visual spot-check, not pixel identity or exhaustive Markdown conformance verification. Full Markdown and syntax highlighting policies are captured in build provenance; the visible sample alone does not prove every grammar's behavior.
- Visible timing is bounded by capture cadence and the detector's stable-frame criterion. Tenths of milliseconds are reporting precision, not submillisecond measurement accuracy; small differences, especially the Hello World cluster around 227 ms, should be treated as effectively tied. Consult p90 and individual observations before interpreting rankings.
- These are warm-cache fresh-process benchmarks of these implementations and this local corpus. System-provided frameworks are excluded from built bundle sizes, while bundled runtimes are included. Physical footprint is measured separately without recording and includes the runner's attributed helper processes; it is not RSS.
- The transcript corpus remains local and is not included in the prebuilt apps. Reproducing the exact chat figures publicly still requires a distributable corpus; another corpus can change results.
- Prebuilt package `bench-2026-09-17-macos-arm64` contains all 19 verified archives, a manifest, and SHA256SUMS. Archive extraction/tree-hash and code-signature checks passed. The local release tag stays on `bdc0ec8fb2dedf5c3fab75bcce7227e4b46a2375`, matching the measured source; this results-document commit is intentionally later. Publishing is pending a GitHub owner/repository because this checkout has no remote. No release has been uploaded.
- Raw evidence and galleries linked above are local, ignored artifacts retained in the isolated release worktree. They are not yet hosted public links. The excluded build-load smoke run is not part of either results table.
