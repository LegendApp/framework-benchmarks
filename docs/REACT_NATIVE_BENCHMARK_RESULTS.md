# React Native benchmark update — September 19, 2026

The updated RN Chat History build measured **393.2 ms** median visible first content versus **398.3 ms** for the saved baseline in the same session: **5.1 ms (1.3%) lower**. This small difference, overlapping samples, and slightly higher internal readiness median do **not** establish a meaningful startup improvement. Switch was 3.9 ms (2.1%) lower; settled footprint was roughly 1 MiB higher. Do not describe this candidate as a demonstrated startup win.

## Same-session RN comparison

Ten measured fresh-process launches per build, separate memory launches, two discarded warmups per build. Fixed bundle paths; alternating baseline/candidate/candidate/baseline order repeated five times. Times are video-derived milliseconds. Negative deltas mean faster.

| Metric | Baseline median | Updated median | Change | Baseline → updated p90 |
| --- | ---: | ---: | ---: | ---: |
| Window | 236.3 | 235.6 | -0.7 ms (-0.3%) | 252.9 → 261.1 |
| First content | 398.3 | 393.2 | -5.1 ms (-1.3%) | 452.7 → 427.7 |
| Jump to top | 48.4 | 50.6 | +2.2 ms (+4.6%) | 55.3 → 63.0 |
| Switch | 186.9 | 183.0 | -3.9 ms (-2.1%) | 193.9 → 192.6 |

| Physical footprint | Baseline MiB | Updated MiB |
| --- | ---: | ---: |
| Initial | 53.1 | 54.1 |
| Top | 57.8 | 58.7 |
| Switched | 65.6 | 66.8 |

App-reported first readiness was 311.3 → 313.6 ms. Discovery-call latency was 6.0 → 3.0 ms, but the updated call adopts work started earlier: this does not mean catalog discovery itself became twice as fast. Initial content-call duration was 87.2 → 89.8 ms.

## Full chat-history reference table

**Only RN was remeasured here.** Other rows retain their earlier measurements: Compose from September 18, all others from September 17, with later app sizes. These are mixed dates/builds, not a synchronized ranking. Compose's latest titlebar/blur changes and several other material/packaging changes postdate those timings. Medians: milliseconds, settled physical footprint in MiB, app sizes excluding external grammars.

| App | Window ms | First content ms | Jump ms | Switch ms | Initial MiB | Top MiB | Switched MiB | App MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 226.9 | 318.9 | 79.1 | 88.3 | 42.4 | 49.0 | 49.0 | 3.2 |
| GPUI | 226.4 | 335.5 | 50.5 | 193.1 | 289.0 | 291.1 | 309.9 | 9.9 |
| **React Native (updated)** | 235.6 | 393.2 | 50.6 | 183.0 | 54.1 | 58.7 | 66.8 | 17.8 |
| Tauri | 244.0 | 544.0 | 70.6 | 218.9 | 363.5 | 370.3 | 394.1 | 11.5 |
| SwiftUI | 268.7 | 668.8 | 68.9 | 554.6 | 82.6 | 83.4 | 93.2 | 3.7 |
| Flutter | 244.3 | 1094.0 | 80.2 | 625.9 | 340.7 | 337.1 | 265.6 | 21.6 |
| Deno WebView | 419.2 | 1268.9 | 72.9 | 657.0 | 408.1 | 415.7 | 582.4 | 65.8 |
| Electron | 261.0 | 1277.7 | 70.5 | 679.0 | 477.5 | 476.2 | 445.8 | 285.6 |
| Deno CEF | 310.4 | 1294.4 | 70.5 | 670.1 | 616.9 | 618.0 | 580.8 | 307.8 |
| Compose | 343.6 | 1277.3 | 83.0 | 326.2 | 786.1 | 793.7 | 947.0 | 116.5 |

RN's external grammar pack is 22.5 MiB (40.3 MiB combined). Hello World was unchanged and was not rerun; its full table remains in the [previous reference report](COMPOSE_BENCHMARK_RESULTS.md#hello-world).

Against the older published RN row (406.3 ms), the updated first-content median is 13.1 ms / 3.2% lower. That cross-session difference must not be attributed to this optimization; the same-session baseline comparison above is the appropriate estimate.

## Validation and limits

- All 20 scored launches passed both normalized content digests, unlocked/on-console checks, recorded frame counts, increasing capture timestamps, encoded/capture timestamp alignment, and all four measured frame-boundary checks. No retries or discarded attempts in this fixed-path pass.
- The initial attempt copied bundles into the canonical installation before each observation and developed additional first-launch latency. It was stopped and excluded as a distinct flawed setup, before completing the replacement 20-observation pass. No completed observation from the fixed-path pass was excluded.
- Each result records the correct variant build manifest and executable path. The two saved builds have different JavaScript bytecode hashes as well as native binaries, so this is an end-to-end build comparison, not proof isolating only the native scheduling edit. Both code paths use the same fixture and rendering policies.
- Apple M4, ARM64, macOS 26.6.1; release builds, warm filesystem caches, fresh processes, normal memory collection. No forced GC or profilers. Other user applications remained running; load-average snapshots are saved, but this run has no continuous per-process CPU/thermal audit. The samples overlap substantially.
- Native startup changes remain uncommitted. Keep this result separate from claims of a proven optimization or an equally optimized, current full-suite ranking.

## Evidence

The portable summary, individual timings, and bundle hashes for this historical run remain in Git history. Raw reports/videos below are ignored machine-local artifacts, not included in a fresh clone. The paired-run scripts and validation logs are under `.build/rn-startup-audit/`.

- baseline 01: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-40-00.255Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-40-00.255Z.json)
- baseline 02: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-42-50.666Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-42-50.666Z.json)
- baseline 03: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-43-16.089Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-43-16.089Z.json)
- baseline 04: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-44-32.459Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-44-32.459Z.json)
- baseline 05: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-44-57.880Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-44-57.880Z.json)
- baseline 06: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-46-14.294Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-46-14.294Z.json)
- baseline 07: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-46-39.748Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-46-39.748Z.json)
- baseline 08: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-47-56.179Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-47-56.179Z.json)
- baseline 09: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-48-21.679Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-48-21.679Z.json)
- baseline 10: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-49-38.078Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-49-38.078Z.json)
- candidate 01: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-41-12.864Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-41-12.864Z.json)
- candidate 02: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-42-25.270Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-42-25.270Z.json)
- candidate 03: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-43-41.534Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-43-41.534Z.json)
- candidate 04: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-44-06.998Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-44-06.998Z.json)
- candidate 05: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-45-23.337Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-45-23.337Z.json)
- candidate 06: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-45-48.791Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-45-48.791Z.json)
- candidate 07: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-47-05.204Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-47-05.204Z.json)
- candidate 08: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-47-30.693Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-47-30.693Z.json)
- candidate 09: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-48-47.138Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-48-47.138Z.json)
- candidate 10: [report and video](../ChatHistory/benchmark/results/2026-09-19T07-49-12.612Z.md) · [raw JSON](../ChatHistory/benchmark/results/2026-09-19T07-49-12.612Z.json)
