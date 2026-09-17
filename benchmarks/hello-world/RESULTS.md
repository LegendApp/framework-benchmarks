> **Latest results:** [September 16 final chat-history and Hello World tables](../final-2026-09-16/RESULTS.md) — 10 observations per app after 2 warmups, videos, separate memory launches, and built app sizes. Earlier tables below are historical.

# Hello World framework baseline — September 12, 2026

5 measured iterations per runtime; 1 discarded warmups. Timing is p50 / p90 in ms; footprint is from a separate launch without recording.

| Runtime | Window ms | Hello World ms | Footprint MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 193.4 / 212.3 | 193.4 / 228.9 | 15.5 | 0.1 |
| SwiftUI | 209.2 / 211.8 | 210.8 / 225.9 | 18.3 | 0.1 |
| React Native | 210.5 / 228.3 | 243.8 / 261.6 | 23.4 | 16.3 |
| Legend Shell | 225.9 / 227.2 | 242.6 / 243.8 | 23.8 | 9.3 |
| Electron | 292.3 / 511.4 | 326.8 / 578.1 | 84.1 | 285.1 |
| Flutter | 243.3 / 261.1 | 245.5 / 277.7 | 55.2 | 33.6 |
| GPUI | 211.0 / 227.9 | 227.3 / 227.9 | 56.5 | 5.3 |
| Deno WebView | 376.9 / 410.7 | 411.8 / 427.3 | 82.5 | 65.0 |
| Deno CEF | 375.2 / 380.0 | 380.0 / 394.6 | 202.4 | 307.0 |

Hello World and the full chat product are distinct workloads. No transcript fixtures, parsing, chat switching, or list work runs in these apps. These are explicit minimal apps, not untouched generator templates.

Raw observations, build provenance, OCR text, cropped videos, text images, and frame timestamps accompany this report. RSS is retained only in JSON as a diagnostic.

## Validation and presentation policy

Both suites now pass process-local `NSAutomaticWindowAnimationsEnabled=NO` before app initialization. No global preferences were changed. The current run used the existing release apps; Tauri was excluded.

All 45 retained videos pass three consecutive OCR matches at confidence ≥0.8, matching frame/timestamp counts, and positive separately measured footprint. All timing and companion memory launches began unlocked. The same three-frame startup detector is retained; differences near one 60 Hz frame should not be overinterpreted.

Seven invalid artifact attempts were discarded under the runner's existing retry policy: one AppKit warmup, two AppKit measured attempts, two Flutter measured attempts, and two Deno CEF measured attempts. End-of-file seeking produced no settled PNG. After this batch, that extraction was fixed to select the recorded reference frame directly, with a passing regression test for a positive timestamp origin. Startup OCR timings were not changed or recomputed. The valid five observations per app remain the reported sample.

Five-second activity logging found no competing Vitest/compiler jobs above 30% CPU during the measured period. Ordinary macOS activity remained, including Spotlight indexing; this is not an exclusive-machine or cold-boot measurement.

[Video gallery](results/2026-09-12T15-34-04.820Z/videos.html) · [All recording links](results/2026-09-12T15-34-04.820Z/videos.md) · [Raw results and provenance](results/2026-09-12T15-34-04.820Z/results.json)

[Previous September 11 run](results/2026-09-11T09-56-59.935Z/results.md).
