# Swift parser and standardized native layouts

AppKit and SwiftUI now default to a Swift implementation of RN’s selective, lazy document algorithm. Catalog discovery remains Swift/Foundation. The shared C++ backend is retained as an optional controlled variant. The table below uses the Swift default for both native apps and the existing C++ backend for RN.

## Fresh three-app results

Times are p50 / p90 milliseconds from five recorded trials per app after one warm-up round. Memory is p50 physical footprint from separate, unrecorded companion launches; values are MiB. These are a small-sample comparison, not a precise estimate of tail latency.

| App | Window | Discovery | First content | Jump to top | Switch | Initial MiB | Top MiB | Switched MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| React Native | 217.6 / 228.0 | 4.2 / 4.8 | 368.8 / 385.0 | 54.0 / 59.4 | 148.1 / 165.4 | 50.3 | 55.6 | 64.4 | 27.3 |
| AppKit | 220.3 / 278.6 | 27.1 / 29.8 | 470.3 / 545.2 | 216.0 / 237.9 | 95.2 / 108.0 | 37.4 | 47.6 | 48.7 | 2.4 |
| SwiftUI | 300.4 / 328.1 | 29.7 / 40.4 | 562.6 / 578.1 | 211.7 / 224.4 | 412.8 / 440.7 | 50.9 | 52.5 | 58.2 | 2.9 |

Observed console lock state: 15/15 recorded trials locked. RN and AppKit came from the joint rotating run. SwiftUI was remeasured separately after correcting its line-height attributes and horizontal List margins. Both batches used the same protocol. The corpus was verified and warmed before measurement. No footprint sampling ran during the recorded timing launches.

RN has the lowest first-content and jump-to-top medians. AppKit has the lowest switch latency and footprint. RN and AppKit window-open medians differ by less than one captured frame. The initial native document totals are about 37–41 ms across all three: the remaining end-to-end differences cannot be described as a broadly slower Swift parser.

## Parser stages

These app-side stage medians diagnose file work; they do not substitute for video-derived readiness. Discovery overlaps other startup work and remains included in first content.

| App | Initial load | Initial scan | Initial parse | Initial native total | Switch native total |
| --- | ---: | ---: | ---: | ---: | ---: |
| React Native | 1.7 | 26.3 | 12.5 | 41.2 | 25.4 |
| AppKit | 1.6 | 20.5 | 18.8 | 41.2 | 42.7 |
| SwiftUI | 1.5 | 17.1 | 18.5 | 37.3 | 27.1 |

## What is standardized

- Owned mapped input, newline offsets, known-envelope fast paths with a general fallback, selective field reading, and deferred message/preview decoding.
- Numeric row identity and metadata caching on demand. SwiftUI iterates indices rather than asking every row for an ID.
- Body and heading typography, Menlo code font, default theme colors, 82% user / 92% assistant maximum widths, user padding, short bubble alignment, collapsed file count, and bounded tool preview requests.
- A local unsaved composer, 88-point composer footprint and 112-point trailing clearance; benchmark metrics no longer consume a separate transcript strip.
- Current-width AppKit text measurement, rendered Markdown caching in both native apps, and explicit SwiftUI layout spacing.
- A 1280-point window and 260-point total sidebar extent. The native pane width accounts for the macOS 26 floating-pane inset.

## Scope of the conclusion

This compares the complete implementations with equivalent document algorithms and common layout policies. It does not isolate framework overhead. Catalog discovery still uses different native implementations, and the Markdown engines and platform controls differ. Swift’s parser result cannot by itself establish an intrinsic language or framework advantage.

RN uses enriched Markdown, AppKit uses attributed text controls, and SwiftUI uses Text with swift-markdown output. Code-block chrome, table rendering, images, some spacing, and native control behavior remain different. The native composer’s demo follows the bottom during streaming; RN’s special user-message anchoring demo is not reproduced. Streaming is outside this startup/top/switch workload. A matching normalized digest proves content parity, not pixel-identical rendering.

## Validation and recordings

- 15 Swift tests passed, including C++/Swift/reference parity on both full histories, lazy metadata/text access, mapped-source lifetime, JSON escaping/reordered envelopes, and demo-stream cancellation.
- AppKit’s actual production UI passed 12 resize/scroll configurations at 1040, 560 and 400 points, plus a full-window geometry regression verifying window width 1280 and transcript x=260, width=1020.
- SwiftUI’s actual production Text and row layout passed body/heading/code height checks (66/28/72 points), a 62-point short user row check, and responsive wrapping checks.
- Release builds, TypeScript checking and all three detector tests passed.
- Detector v4 retains v3’s transcript ROI and three-frame matching rule, but uses settled window bounds for cropping. The runner rejects these three apps if settled width differs from 1280 by more than two points. Earlier smoke/partial runs with wrong AppKit geometry are diagnostic only and are excluded here.

Both pinned normalized digests matched across every accepted iteration: `3a290b9eb53fa834` and `c27e9dc5a848d7f6`. No transcript file was edited.

[Joint RN/AppKit source batch](results/2026-09-11T19-34-29.888Z.json) · [Final SwiftUI source batch](results/2026-09-11T19-47-35.674Z.json) · [RN/AppKit batch tables](results/2026-09-11T19-34-29.888Z.md) · [SwiftUI batch tables](results/2026-09-11T19-47-35.674Z.md)
The original joint batch also contains the intermediate SwiftUI run whose bridged paragraph heights were ignored. That intermediate SwiftUI row is excluded from this combined table.

- React Native: [01](results/2026-09-11T19-34-29.888Z-videos/react-native-01.mp4) · [02](results/2026-09-11T19-34-29.888Z-videos/react-native-02.mp4) · [03](results/2026-09-11T19-34-29.888Z-videos/react-native-03.mp4) · [04](results/2026-09-11T19-34-29.888Z-videos/react-native-04.mp4) · [05](results/2026-09-11T19-34-29.888Z-videos/react-native-05.mp4)
- AppKit: [01](results/2026-09-11T19-34-29.888Z-videos/appkit-01.mp4) · [02](results/2026-09-11T19-34-29.888Z-videos/appkit-02.mp4) · [03](results/2026-09-11T19-34-29.888Z-videos/appkit-03.mp4) · [04](results/2026-09-11T19-34-29.888Z-videos/appkit-04.mp4) · [05](results/2026-09-11T19-34-29.888Z-videos/appkit-05.mp4)
- SwiftUI: [01](results/2026-09-11T19-47-35.674Z-videos/swiftui-01.mp4) · [02](results/2026-09-11T19-47-35.674Z-videos/swiftui-02.mp4) · [03](results/2026-09-11T19-47-35.674Z-videos/swiftui-03.mp4) · [04](results/2026-09-11T19-47-35.674Z-videos/swiftui-04.mp4) · [05](results/2026-09-11T19-47-35.674Z-videos/swiftui-05.mp4)

Source build metadata and checksums are embedded in the raw results. The RN binary is unchanged by this task. Native source and benchmark-policy changes are uncommitted at measurement time. See the [native implementation policy](../../packages/chat-history-swift/README.md) for backend selection and remaining differences.
