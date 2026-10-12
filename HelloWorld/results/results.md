# Hello World reference — September 17–18, 2026

September 17 timing/memory; later packaging sizes; Compose measured September 18. Mixed revisions, not a synchronized rerun. Legend Shell excluded as a duplicate RN host.

Two discarded warmups and ten fresh-process observations per app on Apple M4, ARM64, macOS 26.6.1. Times are video-derived medians in milliseconds; memory is settled physical footprint from separate unrecorded launches. App sizes are logical MiB, exclude symlinks and system frameworks, and include bundled runtimes. No grammar packs.

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
| Compose | 593.8 | 600.5 | 214.6 | 113.3 |

[Summary and p90](summary.json) · [Raw timing runs and size measurements](raw.json). Raw data preserves the original measured bundle sizes; the summary uses the later packaging sizes shown above. Recordings remain machine-local, ignored artifacts.

The raw file keeps per-app `measuredAt` dates, `measurementRuns` provenance for September 17 and 18, and the later `sizeMeasurements`. Small differences near the recording cadence are effectively tied. See the [Compose report](../../docs/COMPOSE_BENCHMARK_RESULTS.md#validation-and-conditions) for its busier host conditions and the [harness methodology](../benchmark/README.md).
