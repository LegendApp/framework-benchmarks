# Responsive AppKit text measurement and SwiftUI diagnosis

September 11, 2026. AppKit now supplies its wrapping text fields with the available text width, and updates it when the transcript column or retained cell frame changes. This is the production implementation, not the earlier fixed-width diagnostic.

## Updated timing comparison

Apple M4, macOS 26.6.1, release builds, unchanged pinned corpus and common native document core. Two discarded warm-ups and five measured iterations per app in rotating order. All 15 timing launches began in a locked console session, explicitly permitted by the existing protocol. Video detector v3 scores the same normalized transcript region for every app. Values are p50 milliseconds.

| App | Window | First content | Jump to top | Switch history |
| --- | ---: | ---: | ---: | ---: |
| AppKit, responsive width | 247.7 | 497.7 | 133.2 | 375.6 |
| SwiftUI, unchanged | 314.4 | 581.0 | 287.0 | 465.5 |
| React Native, unchanged | 246.2 | 379.5 | 46.5 | 155.7 |

The prior corrected AppKit run measured 491.7 ms first content, 169.4 ms top, and 570.8 ms switching. Switching is now **195.2 ms / 34.2% lower**. Startup is effectively unchanged in these small runs. The earlier alternating paired width experiment supports causality; the sequential before/after production runs alone would not isolate all environmental variation.

[Raw timing results](results/2026-09-11T17-23-26.225Z.json) · [15 videos and frame evidence](results/2026-09-11T17-23-26.225Z-videos/) · [Observation journal](results/2026-09-11T17-23-26.225Z.observations.jsonl)

This run measured timing only. Its zero-valued memory fields are placeholders, not memory measurements.

A separate unrecorded AppKit run (one discarded warm-up, three measurements) reports settled physical footprint of **41.0 MiB initially, 41.4 MiB at the top, and 47.0 MiB after switching**. Its internal timing fields are not substituted for the video results. [Memory results](results/2026-09-11T17-33-44.703Z.json)

## What changed in AppKit

The text measurement width is `min(820, column width − leading inset − trailing inset)`, bounded above zero. User messages have a 100-point leading inset; assistant and tool rows have 22 points. The trailing inset is 22 points. The existing 820-point maximum remains; the available column width is dynamic.

New cells receive this input before their first intrinsic-size measurement. Column resizing refreshes visible cells and invalidates cached row heights without creating offscreen cells. Retained cells also refresh the input when their own frame width changes, because AppKit can bring an old cell back without calling the configuration delegate again. Updates invalidate intrinsic sizing only when the preferred width changes materially. Both Markdown and expanded tool text use this path.

A release-mode layout harness exercises the production controller and cells at transcript-container widths of 1040, 560, 400, and back to 1040 points. At every width it scrolls bottom → top → bottom and checks the actual container width, preferred text width, text alignment rectangle, text height, and target-row visibility. All 12 configurations passed, including retained cells after narrowing and widening. The harness supplies an explicit parent width to model the split-view container; it is not a benchmark or a complete settings/UI test.

[Layout evidence](results/2026-09-11-responsive-width/appkit-layout-qa.json) · [Reproducible check](experiments/verify-appkit-layout.py)

## Why SwiftUI is still slower

Its data stage is fast: native work in the updated run is 26.6 ms initially and 22.4 ms on switching, versus AppKit's 33.4 and 37.8 ms. The large remaining difference is after native document creation.

A separate one-second switching sample contains 594 main-thread samples. A major path has 245 samples in a SwiftUI row sizing pass after its List's underlying AppKit table is attached/prepared. Across disjoint call paths, 191 samples are under `NSAttributedString.MetricsCache.metrics`, versus 17 under `RichMarkdownText.body`. These are inclusive sample counts within that interval, not exact percentages of the complete interaction, and the nested counts must not be added together.

The expensive stack runs through SwiftUI `sizeThatFits`, stack layout and preferred spacing, attributed-string bounding rectangles, and Core Text. Rebuilding Markdown inside the view body is avoidable work, but this profile does not support it as the main cause.

A diagnostic `Layout` wrapper forwards size, placement and spacing while timing those queries. During the switched history:

| Work | Observed duration |
| --- | ---: |
| Markdown rendering plus attributed-string conversion, all recorded calls | 15.2 ms |
| Preferred-spacing queries, all recorded calls | 148.3 ms |
| Text-size queries, all recorded calls | 109.2 ms |
| Preferred spacing for long message `row:166` | 112.9 ms |
| Size of that message at proposed width 712 points | 94.8 ms |

That message contains 19,954 Markdown characters (19,163 attributed-text characters in the prior AppKit trace). Its one size result was 7,481 points high. In other words, SwiftUI is doing substantial typesetting for a very tall message even though only a viewport-sized portion can be visible.

This also refines the width explanation: **SwiftUI already receives a finite width in this measurement.** The observed problem is not simply a missing width property. Its preferred-spacing path invokes expensive text metrics in addition to the actual wrapped-size calculation. SwiftUI documents that layout can make multiple proposals and query subview spacing. [Apple Layout documentation](https://developer.apple.com/documentation/swiftui/layout), [Apple custom-layout explanation](https://developer.apple.com/videos/play/wwdc2022/10056/)

[Uninstrumented CPU sample](results/2026-09-11-responsive-width/swiftui-switch-sample.txt) · [Layout-query trace](results/2026-09-11-responsive-width/swiftui-layout-trace.json)

The trace is diagnostic and changes the view graph by adding a forwarding layout. Its numbers explain the sampled call path; they are not substituted for the production timing table. Initial-phase trace records also include the subsequent jump to top. RN's exact benefits from caching, scheduling, and virtualization still have not been independently apportioned.

## Controlled SwiftUI spacing experiment

A second diagnostic compares the same forwarding layout in both variants. The control forwards the text's preferred spacing; the variant returns empty `ViewSpacing` while retaining the text, Markdown renderer, size proposals, and placement. Three paired rounds alternate order; tracing is disabled during these timings.

| Diagnostic variant | Switch samples, ms | Median switch | Median top | Median first content |
| --- | --- | ---: | ---: | ---: |
| Forward preferred spacing | 463.8, 463.3, 464.5 | 463.8 | 289.8 | 563.1 |
| Bypass preferred-spacing query | 341.7, 346.6, 378.9 | 346.6 | 224.5 | 579.5 |

Switching improves **117.2 ms / 25.3%**, consistent with the 112.9 ms query on the long message. The control is also close to the unmodified production SwiftUI result of 465.5 ms. This establishes preferred-spacing measurement as a material contributor, while showing no consistent first-content improvement in this small experiment.

All six paired observations match both content digests. Final-frame visual inspection shows the same visible text and line wrapping, with small position/raster differences; the frames are not pixel-identical. [Visual comparison](results/2026-09-11-responsive-width/swiftui-visual-comparison.json)

This remains a diagnostic. Returning empty preferred spacing is a behavior choice that needs broader layout review before adoption; it is not a general-purpose SwiftUI fix. Production SwiftUI source and the exact original app bundle were restored. The production table above does not include this variant.

[Paired observations](results/2026-09-11-responsive-width/swiftui-spacing-pairs.jsonl) · [Diagnostic patch and instructions](experiments/README.md)

The supported explanation is that these native UI implementations spend more work on automatic row/text measurement for long messages. RN's native measurement integration uses a different path. Neither the AppKit width fix nor this SwiftUI experiment establishes a framework-wide performance ceiling, and neither explains all of RN's remaining advantage.
