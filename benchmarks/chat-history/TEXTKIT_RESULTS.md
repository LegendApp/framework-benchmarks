# Built-in TextKit results — September 12, 2026

AppKit and SwiftUI now use the same built-in NSTextView/TextKit 1 message component. AppKit embeds it directly; SwiftUI retains its List, state, and layout through NSViewRepresentable. The existing Swift Markdown parser and attributed styling remain in place. No third-party rendering dependency was added. React Native is unchanged and was remeasured in the same batch.

## Results

Five measured rounds per app after one warmup, rotating app order. All 15 timing launches recorded a locked console session, as previously authorized. Filesystem caches are warm. Times are video-derived medians in milliseconds, except discovery, which is internally measured. Memory is median physical footprint in MiB, taken in separate companion launches with capture disabled. Memory-launch lock state is not independently retained by the runner.

| App | Window ms | Discovery ms | First content ms | Top jump ms | Switch ms | Initial MiB | Top MiB | Switched MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| react-native | 247.2 | 3.9 | 387.6 | 52.6 | 161.3 | 50.3 | 55.6 | 64.7 |
| appkit | 234.4 | 26.1 | 484.4 | 56.3 | 91.7 | 38.3 | 46.0 | 47.9 |
| swiftui | 301.6 | 30.5 | 552.8 | 175.0 | 381.5 | 52.5 | 57.3 | 65.8 |

[Full statistics and all 15 videos](results/2026-09-12T11-16-39.281Z.md) · [Raw JSON](results/2026-09-12T11-16-39.281Z.json)

RN reaches settled initial content first. AppKit switches first and is close to RN on the top jump. SwiftUI remains slower in these phases even with the shared text control. These results compare complete implementations in this session; they do not isolate the causal improvement from the control replacement. Earlier-day results are not an alternating before/after experiment.

“First content” means the first of three captured frames matching the settled transcript region, not the first visible character. Window appearance animation still contributes to that endpoint. Detector version 4 and the existing 1280-point window are unchanged.

## Implementation

The shared view owns one text storage, layout manager, and text container. Width and content changes invalidate its cached measured size. Measurement and drawing use the same TextKit layout. User bubbles use glyph bounds to remain compact; ordinary usedRect can become container-wide after the NSTextView enters a view hierarchy. SwiftUI answers both ideal and constrained width proposals and no longer converts native attributed strings into SwiftUI AttributedString or measures them with SwiftUI Text.

There is no fixture-specific precomputation, native document preload, custom parser fast path, or new rendering engine in this change. Existing Markdown/source caches remain. Document discovery, document loading, list construction, background-task dispatch, and window animation policies were not changed.

## Validation and scope

- All 16 Swift tests pass with test parallelism disabled, including long-text wrapping, content replacement, glyph bounds, and compact-width checks.
- AppKit: 12 resize/top/tail checks plus full window/sidebar geometry passed.
- SwiftUI: production representable wide/narrow/wide checks preserve content and height; a short user bubble stays compact inside MessageLayout.
- Release builds and packaged ad-hoc signatures succeeded. Final source and binary hashes match the recorded provenance.
- All 15 observations have the expected initial/switched digests, detector v4, a 1280-point window, existing videos, and matching frame/timestamp counts.
- Inspected initial/top/switched smoke frames and final switched frames. The compact-bubble regression found during inspection was fixed; earlier exploratory batches are excluded.

This is not a declaration that every remaining fairness question is resolved. Native tables still use the existing text-row renderer rather than RN's independent table cells. Markdown layout is not pixel-identical across implementations. The previously identified SwiftUI eager-row/worker-dispatch behavior and animation-policy differences are unchanged. Those limitations matter for broader claims about framework cost, even though this task deliberately does not require a complete product.

[Reproduction commands, validation logs, and source/binary hashes](experiments/textkit/README.md). The earlier candidate survey remains in [Markdown library review](MARKDOWN_LIBRARY_REVIEW.md); this implementation follows the subsequent decision to use built-in TextKit instead.
