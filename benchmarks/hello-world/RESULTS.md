# Hello World framework baseline — fresh OCR detector run

Measured September 11, 2026 on Apple M4 (arm64), macOS 26.6.1. Same release builds as the September 10 run.

10 measured iterations per runtime; 2 discarded warmups. Timing is p50 / p90 in ms; footprint is from a separate launch without recording.

| Runtime | Window ms | Hello World ms | Footprint MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: |
| React Native | 230.4 / 245.0 | 234.0 / 246.2 | 21.7 | 16.3 |
| Legend Shell | 233.1 / 248.2 | 241.4 / 248.2 | 22.4 | 9.3 |
| Electron | 500.5 / 531.8 | 575.0 / 615.1 | 81.4 | 285.1 |
| Tauri | 242.8 / 263.5 | 409.7 / 430.2 | 69.8 | 10.3 |
| Deno WebView | 349.1 / 365.8 | 406.7 / 421.6 | 80.0 | 65.0 |
| Deno CEF | 618.3 / 632.1 | 726.6 / 765.5 | 201.2 | 307.0 |
| Flutter | 228.6 / 248.9 | 237.5 / 254.8 | 67.0 | 33.6 |
| GPUI | 217.9 / 236.3 | 233.9 / 237.6 | 41.2 | 5.3 |
| SwiftUI | 230.1 / 244.9 | 239.5 / 249.0 | 17.2 | 0.1 |
| AppKit | 219.0 / 234.0 | 232.8 / 247.5 | 14.7 | 0.1 |

Hello World and the full chat product are distinct workloads. No transcript fixtures, parsing, chat switching, or list work runs in these apps. These are explicit minimal apps, not untouched generator templates.

Raw observations, build provenance, OCR text, cropped videos, text images, and frame timestamps accompany this report. RSS is retained only in JSON as a diagnostic.
## Detector and memory policy

This is a fresh run of all ten release apps using analysis version 2, not an offline reanalysis. First content is the first of three consecutive native-resolution frames where Vision OCR recognizes the greeting with confidence at least 0.8. Window timing uses three changed frames. Startup precision is approximately one 60 Hz frame (16.7 ms), so the 233–241 ms group should be treated as tied rather than ranked by tiny differences.

Memory was measured from separate fresh launches without recording: wait until the corrected visual content boundary, then 2.5 seconds, then take three physical-footprint samples 200 ms apart. The table shows the median across ten launches. App descendants and new WebKit helpers are included; WindowServer is excluded.

OS caches were warm after two discarded warmups. Finder and icon-services background activity was present. These figures describe this machine and these release builds, not cold boots or isolated framework overhead.

## Recordings

All 100 measured startup videos and 20 warmup videos are retained with timestamps, OCR evidence, and text images. No attempts required retries.

- [Video comparison gallery](results/2026-09-11T09-56-59.935Z/videos.html)
- [All measured recordings](results/2026-09-11T09-56-59.935Z/videos.md)
- [Raw results and build provenance](results/2026-09-11T09-56-59.935Z/results.json)
- [Previous run, corrected by offline OCR reanalysis](results/2026-09-11T09-56-59.935Z/../2026-09-10T20-59-54.228Z/results.md)

Raw video artifacts are saved locally under the ignored results directory.
