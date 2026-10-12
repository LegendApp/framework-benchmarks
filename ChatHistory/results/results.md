# Chat History benchmark — September 23–24, 2026

All ten current release apps were rebuilt before this run. Each app has two discarded warmups and ten measured fresh-process timing launches, plus ten separate unrecorded memory launches. Timing is video-derived; memory is settled aggregate macOS physical footprint. No forced garbage collection.

| App | Window ms | First content ms | Jump ms | Switch ms | Initial MiB | Top MiB | Switched MiB | App MiB | Grammar MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 244.1 | 344.3 | 82.6 | 96.7 | 43.6 | 51.2 | 51.2 | 3.2 | 1.3 |
| GPUI | 227.8 | 360.6 | 51.3 | 178.2 | 61.8 | 64.0 | 82.4 | 9.9 | 0.8 |
| React Native | 258.9 | 409.6 | 71.0 | 200.5 | 55.5 | 60.0 | 66.2 | 17.8 | 22.5 |
| Tauri | 275.6 | 609.0 | 73.6 | 227.2 | 139.7 | 146.5 | 170.9 | 11.5 | 0.1 |
| SwiftUI | 291.3 | 676.7 | 81.0 | 556.6 | 85.0 | 85.8 | 92.0 | 3.7 | 1.3 |
| Electron | 294.5 | 1185.8 | 70.6 | 604.1 | 259.0 | 262.5 | 340.9 | 285.6 | 0.1 |
| Flutter | 242.5 | 1209.0 | 80.2 | 753.2 | 105.4 | 113.7 | 119.7 | 21.5 | 0.6 |
| Compose | 626.6 | 1294.0 | 85.0 | 378.8 | 348.6 | 356.3 | 366.1 | 116.5 | 3.4 |
| Deno WebView | 259.6 | 1301.2 | 75.2 | 660.1 | 390.8 | 398.3 | 449.5 | 65.8 | 0.1 |
| Deno CEF | 327.2 | 1360.7 | 71.1 | 687.3 | 410.3 | 413.2 | 471.4 | 307.8 | 0.1 |

## Timing spread

| App | Window p90 ms | First content p90 ms | Jump p90 ms | Switch p90 ms |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 245.6 | 358.7 | 91.9 | 99.1 |
| GPUI | 228.5 | 361.4 | 67.7 | 194.9 |
| React Native | 261.4 | 426.3 | 75.1 | 215.7 |
| Tauri | 278.5 | 611.9 | 78.1 | 237.0 |
| SwiftUI | 295.1 | 711.0 | 172.7 | 560.5 |
| Electron | 492.7 | 1392.7 | 71.0 | 620.4 |
| Flutter | 276.7 | 1235.4 | 81.3 | 754.9 |
| Compose | 643.4 | 1311.7 | 101.5 | 381.5 |
| Deno WebView | 311.4 | 1361.4 | 86.7 | 668.0 |
| Deno CEF | 594.1 | 1577.4 | 86.0 | 704.1 |

## Validation

- All 100 scored videos passed frame-count, monotonic timestamp, encoded/capture timestamp alignment, and measured-frame-boundary checks. Both content digests agree across every scored observation.
- All timing and memory launches passed unlocked/on-console checks. All ten bundle hashes match before and after collection.
- One GPUI timing attempt in round five failed to find stable switched frames. The standard retry passed; the failed attempt is disclosed and excluded from the aggregates. No other attempts failed in this full run.
- SwiftUI’s original saved window frame was restored after collection.

## Conditions and limits

- Current working-tree release builds, including file-backed transcript storage and the current composer implementations. This is not a claim of pixel-identical rendering: GPUI uses a translucent composer without backdrop blur; other apps use their documented glass or blur treatment.
- The initial transcript is 239,115,823 bytes, 32,600 bytes larger than the September 19 corpus. The switched transcript remains 148,125,953 bytes. Cross-date differences cannot be attributed solely to code changes. All apps in this run used the same verified fixtures.
- An earlier attempt stopped during warmups because SwiftUI restored a 1152-point-wide window. Its saved window frame was backed up and temporarily cleared. A separate single-app geometry check confirmed 1280 × 720 before this fresh full run. Neither the failed warmups nor that geometry check enters these aggregates.
- Host CPU during measured collection: median 7.0%, p90 12.7%, maximum 23.9%; thermal states [0] (0 = nominal). This includes benchmark and recording work, not just background activity.
- App sizes exclude external grammar packs; both columns are shown. System frameworks are excluded from bundle sizes. Times use warm filesystem caches and include catalog discovery. Tenths of milliseconds are reporting precision, not submillisecond accuracy.

## Data

[Summary](summary.json) · [Raw observations and build provenance](raw.json). Recordings remain machine-local, ignored artifacts.
