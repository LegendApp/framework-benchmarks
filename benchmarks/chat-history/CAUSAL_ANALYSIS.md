# Why this React Native app is faster — causal investigation

> **Production update:** Responsive AppKit width handling has now been implemented and remeasured. See [updated results and SwiftUI diagnosis](RESPONSIVE_LAYOUT_RESULTS.md). The experiments below describe the earlier investigation.

September 11, 2026. The defensible thesis is that **this React Native implementation uses a more efficient list/text-measurement pipeline for this workload**. Using AppKit underneath does not require using the same table, automatic row sizing, or text-field measurement path as the standalone AppKit implementation. These measurements do not establish that React Native is inherently faster than native code.

## Corrected production measurements

The previous roughly 905 ms AppKit first-content score included a sidebar scrollbar fading out. Treating that entire delay as transcript rendering was incorrect. Detector v3 compares the transcript region only, using the same normalized rectangle for every app (24–98% horizontally, 14–98% vertically), with three consecutive matching captured frames. Window detection remains separate. This is settled visible-content timing, not a universal framework startup metric.

Production release builds, Apple M4/macOS 26.6.1, identical corpus and native document core; one discarded warm-up and five measured iterations per app in rotating order. All 15 launches began in the same locked console session. Results are p50 milliseconds:

| App | Window | First content | Jump to top | Switch history | Initial native data work |
| --- | ---: | ---: | ---: | ---: | ---: |
| AppKit | 245.0 | 491.7 | 169.4 | 570.8 | 32.5 |
| SwiftUI | 328.4 | 578.4 | 288.5 | 462.4 | 25.8 |
| React Native | 260.0 | 411.7 | 46.8 | 155.4 | 39.6 |

RN first content is 80 ms (16%) lower than AppKit here, not twice as fast. RN switching latency is 73% lower (3.67× ratio). Five samples support this workload comparison, not a broad ranking across machines and apps. SwiftUI first content is now slower than AppKit; the previous apparent ordering was confounded by the detector.

This was a timing-only run: zero-valued memory fields in its raw output mean **not measured**, not zero memory use. Use the earlier separate memory run for memory figures, with its documented mixed session conditions.

[Raw results](results/2026-09-11T15-02-53.805Z.json) · [Videos and frame evidence](results/2026-09-11T15-02-53.805Z-videos/) · [Observation journal](results/2026-09-11T15-02-53.805Z.observations.jsonl)

## 1. A measurement artifact explained most of the old startup gap

The old full-window matcher allowed a changed-pixel ratio of 0.004. The sidebar scrollbar alone changed approximately 0.005 of the image after the transcript was already stable. It therefore held the content score back until the scrollbar disappeared.

In three baseline launches, scoring the **same captured frames** gave:

| Trial | Old full-window first content | Transcript-only first content | Artificial delay |
| --- | ---: | ---: | ---: |
| 1 | 884.4 | 517.7 | 366.7 |
| 2 | 919.7 | 503.0 | 416.7 |
| 3 | 878.5 | 528.5 | 350.0 |

A paired diagnostic that hid only the sidebar scroller made the old and corrected scores agree. The transcript content and its digest were unchanged. This is direct evidence of detector sensitivity to decoration, not an AppKit rendering limitation.

Detector v3 retains the legacy scores, the source timestamp of every frame, and the region specification. Exported videos preserve frame count with passthrough frame timing. Regression tests cover sidebar animation, missing/moving transcript text, and the three-frame requirement.

[Scroller pairs](results/2026-09-11-causal/chat-appkit-scroller-pairs.jsonl)

## 2. The real AppKit switching bottleneck is automatic text sizing

A one-second switching sample found **472 of 655 main-thread samples** inside this path:

```
NSTableView.scrollRowToVisible
  → automatic row-height calculation
  → Auto Layout
  → NSTextField.intrinsicContentSize
  → NSTextFieldCell.cellSizeForBounds
  → NSAttributedString.boundingRect
  → Core Text typesetting / glyph work
```

This fraction describes the sampled interval, not all app CPU time. A separate draw/layout trace showed only eight tail cells being configured. One contained **19,163 characters** of attributed text. Cell configuration finished near 15 ms into the traced update, but the table layout did not return until approximately 400 ms. The hypothesis that switching was primarily wasting time building all the top rows was not supported.

The AppKit implementation uses `NSTableView.usesAutomaticRowHeights`, wrapping `NSTextField` labels, and an Auto Layout maximum-width constraint, but no `preferredMaxLayoutWidth`. A constraint limiting a view's width and a preferred width for intrinsic text measurement are distinct inputs. Apple documents that the latter determines wrapping during intrinsic-size calculation; its default is zero. [Apple documentation](https://developer.apple.com/documentation/appkit/nstextfield/preferredmaxlayoutwidth)

A controlled variant supplied only `preferredMaxLayoutWidth = 820`, the existing maximum at the tested window size. Same text, parser, renderer, and content digests; three alternating-order paired runs:

| AppKit variant | Switch samples, ms | Median, ms |
| --- | --- | ---: |
| Baseline | 563.5, 562.7, 568.7 | 563.5 |
| Explicit preferred wrapping width | 390.1, 374.5, 382.2 | 382.2 |

That is **181 ms / 32% less visible switching latency** from a text-measurement change alone. It establishes this sizing path as a material cause. It does not explain the entire remaining RN advantage. Initial content stayed around 511 ms in these paired trials.

Visual inspection of the final paired frames confirmed the same visible text and wrapping; the frames are not pixel-identical (small positioning/raster differences remain). Content digests alone would not establish visual equivalence.

The fixed width is a diagnostic, not a shipped responsive-layout fix. The original AppKit UI and production bundle were restored. A product fix should derive the measurement width from actual available width and handle resize invalidation.

[CPU sample](results/2026-09-11-causal/chat-appkit-switch-sample.txt) · [Layout trace](results/2026-09-11-causal/chat-appkit-switch-baseline-video.json) · [Text lengths](results/2026-09-11-causal/chat-appkit-text-length-video.json) · [Width experiment](results/2026-09-11-causal/chat-appkit-bounded-pairs.jsonl) · [Reproduction patch](experiments/README.md)

## 3. React Native uses a different native path

Source inspection of the shipped RN implementation shows:

- LegendList uses sparse row access, estimated item sizes, recycling, and initial scrolling at the end. It controls which items need layout.
- Fabric supplies explicit layout constraints to the enriched Markdown shadow node.
- The Markdown library measures native attributed text with an explicitly sized `NSTextContainer`, `NSLayoutManager`, and `NSTextStorage`. It can measure without creating an AppKit view, and keeps a measurement cache keyed by relevant properties and width.
- A switching CPU sample found native text layout on the React runtime thread. This is native text work invoked through the RN pipeline; it is not JavaScript implementing a faster typesetter.

Relevant source in the sibling `legend-apps` repository: `apps/chat-history/src/App.tsx`, `TranscriptDataSource.ts`, `TranscriptRow.tsx`; the installed `react-native-enriched-markdown` package's `ios/internals/EnrichedMarkdownTextShadowNode.mm`, `ShadowMeasurementUtils.h`, and `ENRMViewFreeMeasurement.h`. Fabric is enabled in `shell/macos/Podfile`.

This agrees with RN's documented separation of C++ layout, host text measurement, and native-view mounting. [React Native render pipeline](https://reactnative.dev/architecture/render-pipeline)

The width ablation establishes causality for AppKit sizing. Source and samples establish the different RN architecture. **The individual benefits of RN caching, concurrency, and list policy have not been separately quantified**, so assigning all of the remaining gap to any one of them would overstate the evidence.

Native data loading is not the main explanation after the shared-core optimization: AppKit's initial native work is 32.5 ms versus RN's 39.6 ms. SwiftUI is 25.8 ms. Their slower visible outcomes arise after that stage; the detailed causal profile here is AppKit-specific, not proof of SwiftUI's exact bottleneck.

## Checks and limits

Window-animation, layer-backing, callback scheduling, forced display/flush, and immediate-bottom-scroll probes did not remove the relevant delay. Those were exploratory probes, not independently replicated framework benchmarks. Startup sampling was mostly idle, which contradicted the original interpretation of hundreds of milliseconds of continuous startup CPU work.

All 15 production observations matched both expected content digests, and saved video frame counts match their source timestamp arrays. The detector has three passing regression tests. The wider task's native parser change has 13 passing Swift tests, including current-corpus parity. Raw histories and private rendered content remain in ignored local artifacts.

The result supports: **“Our React Native app is faster on this chat workload because its native list/text-layout integration performs the work more efficiently than our AppKit table implementation. Supplying AppKit a preferred text width alone removes about a third of its switching latency.”**

It does not support: “React Native is fundamentally faster than AppKit.” AppKit and SwiftUI can adopt explicit-width measurement, caching, and more deliberate virtualization. The remaining gap needs further controlled ablations before claiming a complete explanation.
