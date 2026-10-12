# Desktop comparison — Compose measurements added September 18, 2026

**Only Compose was measured in this run.** Its rows use the current audited release apps and the full protocol: two discarded warmups, ten measured fresh-process launches per workload, video-derived visible times, and separate unrecorded memory launches. The other frameworks retain September 17 timing and memory, with later app sizes; the [Hello World reference data](../HelloWorld/results/) preserves those measurements. Their timings predate subsequent packaging, sidebar and composer changes. These mixed-revision tables are a reference, not a new synchronized framework ranking.

Times below are medians in milliseconds. Memory is settled physical footprint in MiB, not peak or RSS; size is logical installed app bytes in MiB. The system JVM is not used by exported Compose apps: the bundled JVM and Skia count toward app size. No profiling, forced collection, special heap cap or prewarming ran in these measurements. Filesystem caches were warm, as in the standard protocol.

## Chat history

| App | Window ms | First content ms | Jump ms | Switch ms | Initial MiB | Top MiB | Switched MiB | App MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 226.9 | 318.9 | 79.1 | 88.3 | 42.4 | 49.0 | 49.0 | 3.2 |
| GPUI | 226.4 | 335.5 | 50.5 | 193.1 | 289.0 | 291.1 | 309.9 | 9.9 |
| React Native | 243.4 | 406.3 | 45.0 | 157.7 | 52.8 | 57.8 | 66.5 | 17.8 |
| Tauri | 244.0 | 544.0 | 70.6 | 218.9 | 363.5 | 370.3 | 394.1 | 11.5 |
| SwiftUI | 268.7 | 668.8 | 68.9 | 554.6 | 82.6 | 83.4 | 93.2 | 3.7 |
| Flutter | 244.3 | 1094.0 | 80.2 | 625.9 | 340.7 | 337.1 | 265.6 | 21.6 |
| Deno WebView | 419.2 | 1268.9 | 72.9 | 657.0 | 408.1 | 415.7 | 582.4 | 65.8 |
| Electron | 261.0 | 1277.7 | 70.5 | 679.0 | 477.5 | 476.2 | 445.8 | 285.6 |
| Deno CEF | 310.4 | 1294.4 | 70.5 | 670.1 | 616.9 | 618.0 | 580.8 | 307.8 |
| **Compose (new)** | 343.6 | 1277.3 | 83.0 | 326.2 | 786.1 | 793.7 | 947.0 | 116.5 |

Compose's external syntax pack adds **3.4 MiB**, for **119.9 MiB** combined installed size. App sizes exclude external grammar packs for every framework; the linked size report lists the other packs.

## Hello World

| App | Window ms | First content ms | Memory MiB | App MiB |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 193.4 | 193.4 | 15.5 | 0.1 |
| GPUI | 210.7 | 226.5 | 56.3 | 5.3 |
| SwiftUI | 210.9 | 227.5 | 18.3 | 0.1 |
| React Native | 210.9 | 227.6 | 23.3 | 7.2 |
| Flutter | 234.4 | 259.2 | 55.0 | 17.0 |
| Electron | 277.6 | 344.5 | 83.4 | 285.1 |
| Deno CEF | 359.3 | 360.0 | 203.6 | 307.0 |
| Deno WebView | 360.9 | 394.1 | 83.0 | 65.0 |
| Tauri | 377.5 | 409.8 | 73.0 | 10.3 |
| **Compose (new)** | 593.8 | 600.5 | 214.6 | 113.3 |

Hello World has no grammar pack. Legend Shell is excluded as a duplicate RN host.

## Compose timing spread

| Workload | Metric | Median ms | p90 ms |
| --- | --- | ---: | ---: |
| Chat history | windowOpenMs | 343.6 | 344.4 |
| Chat history | firstContentMs | 1277.3 | 1344.0 |
| Chat history | topJumpMs | 83.0 | 95.0 |
| Chat history | switchContentMs | 326.2 | 331.5 |
| Hello World | windowOpenMs | 593.8 | 633.4 |
| Hello World | firstContentMs | 600.5 | 633.4 |

## Validation and conditions

- Apple M4, ARM64, macOS 26.6.1. Source was unchanged during collection. The app code corresponds to `fb09202`; exported build records preserve their original build-time revision/working-tree provenance rather than relabeling it after commit.
- Ten completed timing observations and ten companion memory observations per workload. Every checked console session was unlocked and on-console. No discarded chat attempts; Hello World measured recordings all succeeded on attempt 1. Warmups are excluded.
- All 20 measured videos passed frame counts, strictly increasing capture timestamps, encoded timestamp alignment and measured-boundary checks. Both chat digests match in every iteration (`3a290b9eb53fa834`, `c27e9dc5a848d7f6`); all Hello World OCR checks matched the greeting.
- Host monitoring started during the first measured chat round, so it does not cover the warmups or a quiet preflight. Across 103 samples, whole-host CPU median/p90 was **18.7% / 24.7%**, maximum **34.5%**; every thermal sample was nominal. These include application, capture and analysis work. Background Codex and simulator processes were present. This run is not a replication of the earlier run's quieter host conditions.
- With ten samples and video frame quantization, decimal places are reporting precision, not submillisecond accuracy. Cross-run differences can reflect build changes, filesystem/OS caches and background activity. Neither these results nor the earlier rows establish intrinsic framework superiority.

## Saved evidence

- [Chat raw results](../ChatHistory/benchmark/results/2026-09-18T21-43-22.207Z.json) · [Chat report and ten recordings](../ChatHistory/benchmark/results/2026-09-18T21-43-22.207Z.md)
- [Hello World raw results](../HelloWorld/benchmark/results/2026-09-18T21-49-08.566Z/results.json) · [Hello World video gallery](../HelloWorld/benchmark/results/2026-09-18T21-49-08.566Z/videos.html)
- [Validation summary](../.build/compose-full-validation.json) · [Run log](../.build/compose-full-benchmark.log) · [Host samples](../.build/compose-full-host.jsonl)

Raw results and recordings are ignored machine-local artifacts; links work in this checkout, not a fresh clone. [Implementation and optimization audit](COMPOSE_MULTIPLATFORM.md).
