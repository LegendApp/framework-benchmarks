# Chat history benchmark — September 15, 2026

> Subsequent source changes align the web list revision/settings and code-pane text handling. See [rendering-work audit](RENDERING_WORK_ALIGNMENT.md). The measurements below remain valid for their frozen binaries; they do not include those later changes.

Current recorded comparison of the nine frozen, syntax-highlighting-enabled production builds. This supersedes the September 13 single-launch checks for performance reporting. Hello World was not rerun.

Apple M4, arm64, macOS 26.6.1. Two discarded warmup rounds, then ten measured rounds per app in rotating order: **90 recorded timing launches and 90 separate unrecorded memory launches**. Every measured launch was unlocked. Fixture verification warms the filesystem cache; these are fresh-process, warm-filesystem measurements, not cold-boot startup.

## Results

Times are video-derived median milliseconds. Memory is median aggregate macOS physical footprint in **MiB**, not RSS. Bundle size is logical uncompressed file size.

| App | Window | First content | Jump to top | Switch | Initial MiB | Top MiB | Switched MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 228.5 | 332.4 | 73.7 | 86.4 | 41.7 | 48.2 | 48.3 | 4.6 |
| GPUI | 227.4 | 377.4 | 50.7 | 199.3 | 289.2 | 291.1 | 309.8 | 10.8 |
| React Native | 245.1 | 411.5 | 44.6 | 164.0 | 52.6 | 57.1 | 66.9 | 42.1 |
| Tauri | 261.1 | 610.1 | 72.5 | 214.9 | 363.2 | 369.8 | 395.2 | 11.6 |
| SwiftUI | 276.4 | 681.0 | 57.2 | 617.2 | 82.3 | 83.3 | 91.4 | 5.1 |
| Flutter | 252.7 | 1153.0 | 81.4 | 668.4 | 329.9 | 341.4 | 270.3 | 48.0 |
| Electron | 295.1 | 1361.7 | 56.1 | 713.2 | 469.9 | 475.6 | 441.1 | 286.2 |
| Deno WebView | 284.6 | 1384.6 | 80.5 | 676.6 | 407.9 | 415.3 | 582.0 | 65.9 |
| Deno CEF | 486.0 | 1561.4 | 72.0 | 690.8 | 610.2 | 620.2 | 576.2 | 307.8 |

## Timing spread

p90 means the 90th percentile of the ten completed observations.

| App | Window p90 | First content p90 | Jump p90 | Switch p90 |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 243.9 | 344.8 | 84.2 | 101.3 |
| GPUI | 245.4 | 432.8 | 57.8 | 205.4 |
| React Native | 261.8 | 428.0 | 49.4 | 177.9 |
| Tauri | 294.0 | 710.7 | 75.7 | 238.6 |
| SwiftUI | 328.8 | 794.5 | 93.0 | 624.0 |
| Flutter | 294.8 | 1228.1 | 81.9 | 701.3 |
| Electron | 561.1 | 1727.5 | 71.9 | 722.8 |
| Deno WebView | 328.8 | 1528.3 | 86.0 | 697.0 |
| Deno CEF | 676.2 | 1809.6 | 74.0 | 972.0 |

## Interpretation

React Native reached first content in **411.5 ms median, 428.0 ms p90**. The September 13 locked, unwarmed 1,144 ms observation was not representative of this repeated run. The earlier September 12 RN median was 444.1 ms, but changes in code, session conditions, and catalog contents prevent attributing the difference to one change.

AppKit was faster than RN for first content (332.4 versus 411.5 ms), used less initial memory (41.7 versus 52.6 MiB), and switched faster (86.4 versus 164.0 ms). RN reached first content faster than SwiftUI (681.0 ms), and had the lowest median top-jump time in this run. GPUI also reached first content faster than RN (377.4 ms), with higher memory use. These are results for these applications and this workload, not intrinsic framework rankings.

## Internal stage diagnostics

Median native document preparation and remaining content-open time, in milliseconds. These are internal diagnostics, not additional time to add to the visible startup metric. Post-native includes bridge work and layout/render submission, including highlighting where performed there.

| App | Initial native | Initial post-native | Switch native | Switch post-native |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 41.3 | 24.4 | 35.2 | 12.3 |
| GPUI | 133.2 | 52.4 | 114.5 | 57.7 |
| React Native | 40.0 | 37.2 | 27.6 | 54.4 |
| Tauri | 115.0 | 97.1 | 104.9 | 126.7 |
| SwiftUI | 40.9 | 351.4 | 40.7 | 545.7 |
| Flutter | 792.2 | 141.8 | 529.5 | 162.9 |
| Electron | 901.6 | 67.5 | 590.4 | 124.3 |
| Deno WebView | 854.8 | 114.5 | 566.9 | 126.1 |
| Deno CEF | 852.2 | 96.7 | 568.6 | 136.6 |

## Validation and limits

- All nine apps returned identical normalized transcript digests: `3a290b9eb53fa834` initially and `c27e9dc5a848d7f6` after switching. The two pinned history-file hashes were verified before collection.
- Detector v4 uses the transcript region and the first of three frames matching the settled view. All 90 recordings decoded, with monotonic source timestamps and video timestamp alignment within 0.1 ms. Deno CEF iteration 3 has one extra trailing video frame after the timestamped sequence; the measured frames align and are unaffected.
- Memory uses three settled samples per phase in a separate launch, including attributable child/WebKit helper processes. Capture surfaces are excluded by keeping capture disabled in those launches.
- Five failed timing attempts were discarded and retried: Electron round 1 (one), Flutter round 3 (two), AppKit round 4 (one), Deno WebView round 8 (one). Every app has ten completed observations. The existing harness logs retry counts but not intermediate exception reasons, so these are completed-launch performance results, not failure-rate estimates.
- All benchmark executables had identical before/after SHA-256 hashes. The report embeds build provenance and links to source hash snapshots. The sibling repository changed during collection, including its EnrichedMarkdown patch; those edits are not in the frozen binaries. These results describe the exported builds, not all source currently on disk.
- The machine was not isolated from other work. Concurrent source changes were observed, but background CPU/thermal conditions were not continuously recorded. Treat small gaps and p90 values as specific to this session; this is not a controlled causal experiment on highlighting.
- Highlighting is enabled across all targets under the shared language/size policy, but the lexer and renderer libraries differ. Parser parity establishes normalized content equivalence, not pixel identity. See [highlighting policy and visual audit](SYNTAX_HIGHLIGHTING.md).

## Evidence

- [Raw results and full protocol](results/2026-09-15T19-28-19.131Z.json)
- [Generated detailed tables](results/2026-09-15T19-28-19.131Z.md)
- [Observation journal](results/2026-09-15T19-28-19.131Z.observations.jsonl)
- [Validation, source hashes, and binary hashes](results/2026-09-15T19-28-19.131Z.validation.json)
- [Complete run log](results/2026-09-15T19-28-19.131Z.run.log)
- [Video comparison viewer — all 90 recordings](results/2026-09-15T19-28-19.131Z-videos/index.html)
