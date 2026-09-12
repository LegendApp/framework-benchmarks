# Where the platform timing differences come from

Historical investigation: subsequent production changes and current measurements are in [TextKit results](TEXTKIT_RESULTS.md). Diagnostic sources and raw evidence linked below are retained locally and are not part of the committed report.

September 11, 2026. Baseline commit: `7de0f85` in `chat-history-comparison`; RN source and production binary unchanged during this investigation.

**The startup ranking combines three different effects: AppKit’s window presentation, SwiftUI’s scheduling and list construction, and different native text-measurement pipelines. It is not evidence that JavaScript executes the same work faster than Swift.**

The most useful new findings are:

- AppKit’s approximately 100 ms first-content disadvantage can be reproduced by its opening animation. Turning that animation off removes approximately 104 ms in an alternating controlled experiment, using the same executable.
- SwiftUI constructs every row body despite the lazy document model. Making the outer row structure fixed reduces eager Markdown work and improves startup/switching, with a top-jump regression in the tested variant.
- SwiftUI also delays starting its parsing worker while main-actor work runs. Background execution and immediate background dispatch are different properties.
- The native text APIs themselves differ dramatically. On the same 19,163-character attributed message, measurement took about 104 ms through `NSTextField`, 132 ms through SwiftUI `Text`, and 7.5 ms through a fresh TextKit stack, all called from Swift.
- RN’s GitHub Markdown component uses segmented native rendering and TextKit measurement, including work off the main thread and a measurement cache. It does not take the standalone apps’ text-field/SwiftUI-Text path and then add JavaScript overhead to it.

No experimental optimization has been applied to the production apps. The committed benchmark remains the baseline; diagnostic builds and recordings are separate.

## 1. Start with the actual production measurements

Five recorded trials per app after warm-up. Milliseconds are medians; memory is initial physical footprint in MiB from separate unrecorded launches. These remain the production results, not a new ranking assembled from experimental variants.

| App | Window visible | Settled first content | Jump to top | Switch history | Initial memory |
| --- | ---: | ---: | ---: | ---: | ---: |
| React Native | 217.6 | 368.8 | 54.0 | 148.1 | 50.3 |
| AppKit | 220.3 | 470.3 | 216.0 | 95.2 | 37.4 |
| SwiftUI | 300.4 | 562.6 | 211.7 | 412.8 | 50.9 |

The detector measures the first of three frames matching the settled transcript region. “First content” here means **settled visible content**, not the first pixel of text and not a pure CPU-startup metric. Opening animation can legitimately affect this endpoint even when the text is already calculated.

Recomputing intervals within each original trial gives:

| Interval | React Native | AppKit | SwiftUI |
| --- | ---: | ---: | ---: |
| Launch → document-open start | 223.0 | 223.7 | 298.1 |
| Document-open start → internal readiness | 69.2 | 58.6 | 210.1 |
| Native document work, included in the preceding interval | 41.2 | 41.2 | 37.3 |
| Internal readiness → settled captured content | 67.4 | 190.2 | 38.8 |

Each cell is a median of the corresponding per-trial interval. Medians of intervals need not sum to the median total. Readiness callbacks also have different definitions across apps: AppKit explicitly lays out/displays, SwiftUI waits after tail appearance, and RN waits after tail layout. They locate possible delays; controlled variants and captured frames establish the visible effect.

**AppKit is not spending an extra 100 ms parsing or preparing the initial tail.** Its open-to-readiness interval is already shorter than RN’s. SwiftUI, in contrast, has substantial work/waiting before that readiness boundary.

[Production report and all original videos](SWIFT_PARITY_RESULTS.md) · [Per-trial interval summary](results/2026-09-11-platform-profile/production-decomposition.json)

## 2. AppKit: separate presentation from transcript computation

### Opening animation accounts for the startup disadvantage in the controlled test

The only experimental toggle is `window.animationBehavior = .none`, set before `makeKeyAndOrderFront`. Both conditions use the same diagnostic executable, tracing disabled, with three trials each in baseline/variant, variant/baseline, baseline/variant order. No sampling or footprint collection runs during these recordings.

| AppKit condition | Window visible | Settled first content | Readiness → captured content | Top jump | Switch |
| --- | ---: | ---: | ---: | ---: | ---: |
| Normal opening animation | 245.8 | 479.1 | 158.6 | 174.2 | 86.9 |
| Opening animation disabled | 258.3 | 375.0 | 44.6 | 194.6 | 92.9 |
| Difference, disabled minus normal | +12.5 | −104.2 | −114.0 | +20.4 | +6.1 |

This directly supports a presentation explanation for the startup difference. It is not a general throughput improvement: top jump and switching did not improve. An earlier independent three-trial no-animation batch had a 363.1 ms first-content median. Use the alternating experiment for the controlled effect size, not a cross-batch subtraction against RN.

Apple defines this property as controlling automatic animation when ordering a window into or out of view. The result is consistent with that documented behavior. [NSWindow animation behavior](https://developer.apple.com/documentation/appkit/nswindow/animationbehavior-swift.enum)

The previous investigation’s exploratory animation probe did not establish this effect. That was a different app/layout baseline, and was not replicated as a controlled pair. This new result supersedes the broad inference that presentation could not explain the remaining startup gap.

### Initial tail rendering is small; top-of-history text is expensive

Instrumented AppKit launches, excluding the first launch, show the following. Durations are inclusive wall time, not additive CPU buckets.

| Operation | Initial tail | Jump to top | Switched tail |
| --- | ---: | ---: | ---: |
| Transcript cell requests | 10 | 7 | 7 |
| Newly materialized row metadata | 9 | 7 | 6 |
| Markdown conversions | 6 | 5 | 4 |
| Markdown parse + attributed output | 1.67 ms | 2.93 ms | 0.35 ms |
| Cell creation/configuration, including Markdown above | 6.90 ms | 7.35 ms | 2.98 ms |
| Text intrinsic-size calls | 24 | 9 | 16 |
| Time inside those size calls | 0.58 ms | 114.51 ms | 1.92 ms |
| Explicit final layout/scroll/display routine | 15.36 ms | — | 9.48 ms |

A 2,307-character message accounts for repeated roughly 21 ms intrinsic-size calculations at the top; another 2,719-character attributed message costs about 14 ms per calculation. Short initial and switched tail messages are cheap. This explains why one platform’s switch score cannot predict its top-jump score.

A separate sampled top jump follows:

```text
NSTableView.scrollRowToVisible
  → visible-row preparation / automatic row heights
  → Auto Layout
  → NSTextField.intrinsicContentSize
  → NSAttributedString.boundingRect
  → NSCoreTypesetter / CTLineCreateWithAttributedString
  → glyph encoding, OpenType positioning and kerning
```

Providing a preferred wrapping width fixed the earlier pathological width problem, but does not bypass this intrinsic-measurement implementation or prevent repeated requests. Source-level cell configuration is no longer the dominant cost here.

The launch trace also measured approximately 26 ms in `NSApplication.shared`, 72 ms in `applicationDidFinishLaunching` overall, including 6 ms constructing the root and 12 ms attaching it to the window. `makeKeyAndOrderFront` itself returned in about 1.4 ms. **Its call duration does not include the animation subsequently presented by the window system.** These nested durations do not account for all pre-main/LaunchServices work.

## 3. SwiftUI: three separate sources of latency

### A lazy backing store does not guarantee lazy view construction

The production `TranscriptRow.body` switches among different root view structures. `List` visits those bodies while determining row structure. The trace records every one of the 162 initial row bodies and every one of the 174 switched row bodies before readiness; this is not the background content-digest check touching the model.

| Before readiness | Initial document | Switched document |
| --- | ---: | ---: |
| Row bodies evaluated | 162 / 162 | 174 / 174 |
| Markdown messages converted | 111 | 126 |
| Decode lazy message strings | 1.81 ms | 1.51 ms |
| Parse Markdown AST | 4.14 ms | 7.77 ms |
| Render native attributed strings | 10.23 ms | 17.08 ms |
| Convert/map SwiftUI attributed text, including line heights | 26.95 ms | 42.55 ms |
| Text-size calls | 34 | 31 |
| Time inside text-size calls | 12.85 ms | 163.90 ms |

Metadata construction itself is only about 0.05 ms. The expensive consequence is eagerly following that metadata into Markdown and attributed-text conversion.

Removing `.id(index)` did **not** restore laziness. Giving the row a fixed outer `VStack(spacing: 0)` in a small wrapper did: around 39/36 body evaluations, 29/29 newly requested metadata rows, and 20/21 Markdown conversions remained. Apple documents why a constant number of views per `ForEach` element allows `List` to identify rows without building all their content. [Apple’s explanation](https://developer.apple.com/videos/play/wwdc2023/10160/?time=1162), [ForEach documentation](https://developer.apple.com/documentation/swiftui/foreach)

However, fewer conversions did not mean every visible operation became faster. A fresh alternating video comparison using **uninstrumented UI sources**, with all six trials passing the runner’s unlocked-session requirement, produced:

| SwiftUI condition, three trials each | First content | Top jump | Switch |
| --- | ---: | ---: | ---: |
| Production row structure | 656.8 ms | 199.0 ms | 430.1 ms |
| Fixed outer row structure | 586.8 ms | 219.1 ms | 380.0 ms |

First content improved by 70 ms and switching by 50 ms, while jumping to the top worsened by 20 ms. The changed list construction also changes which rows it prepares and when presentation settles. A side-by-side review of the initial, top and switched frames showed the same intended content but some vertical placement differences; this is not a pixel-identical replacement. This variant is evidence about SwiftUI’s behavior, **not a justified production fix yet**. Earlier SwiftUI recording batches mixed locked and unlocked sessions and gave a misleading startup direction. They are retained as exploratory evidence only and excluded from this table. The verified batch’s absolute times differ from the original production batch; only compare the two conditions within this table.

### Starting the worker is delayed by main-actor scheduling

The current store starts a main-actor `Task`, which then creates and awaits `Task.detached`. During loading transitions, the outer task waits behind other main-actor work.

| Traced interval | AppKit initial / switch | SwiftUI initial / switch |
| --- | ---: | ---: |
| Request → parser worker starts | 0.01 / 0.04 ms | 34.84 / 56.76 ms |
| Worker finishes → main-thread result delivery | 0.04 / 0.04 ms | 0.02 / 0.02 ms |
| Delivered document → last-row appearance | — | 109.44 / 281.92 ms |

The delay is before the worker starts, not waiting for its completed result. Catalog loading exhibits a similar startup scheduling distinction: in the traced SwiftUI baseline, store initialization happens around 173 ms after launch, but its catalog task starts around 265 ms. In AppKit, catalog work starts around 194 ms and document work around 227 ms. These diagnostic launch timelines are separate from the production video batch.

A diagnostic variant creates `Task.detached` immediately, then awaits that existing task from the main-actor task. In three post-warm-up traces, request-to-worker latency fell to 0.01 ms initially and 0.03 ms on switching. Internal open-to-readiness fell from 191.1 to 158.0 ms initially and from 379.3 to 338.5 ms on switching. These are unrecorded, separately collected diagnostic series—not a new video-derived benchmark. The lightweight trace runner did not retain per-launch lock state, so the total-latency comparison is indicative only. The near-immediate worker start in the changed code is directly observed; its exact foreground benefit still needs a controlled recorded run.

### Long-message sizing dominates the switched viewport

The text-size trace identifies row 166 of the second fixture, a user message with 19,163 rendered characters: approximately 124–127 ms in one `Text.sizeThatFits` call at a 757.66-point proposal. Nearby row 165, with 12,500 characters, adds about 15 ms. The document has only 174 display rows, so a small amount of lookahead near the bottom can encounter large individual messages.

At the top, total SwiftUI text sizing is about 116 ms. A separate CPU sample follows `List`/hosting layout through `StyledTextLayoutEngine.sizeThatFits`, `ResolvedStyledText.StringDrawing`, and Core Text glyph/line construction. The remaining cost is not primarily JSON parsing, nor merely counting Swift structs.

## 4. React Native: a different use of the same native platform

The RN app uses LegendList with `initialScrollAtEnd`, recycling, sparse metadata access, estimated item size 500 and an estimated viewport. These are explicit list policies; they are not features implied by using React alone.

Messages pass a native Markdown block ID to the renderer. Text stays in the native document registry and is fetched by the native Markdown provider, avoiding conversion of the entire transcript into JavaScript strings. The Swift apps also retain native lazy text, so this avoids a potential RN penalty rather than proving an advantage over Swift.

An important source detail: although the public JSX component is called `EnrichedMarkdownText`, `flavor="github"` selects the native **segmented `EnrichedMarkdown` component**. Its view-free measurement parses Markdown, divides it into segments, and measures text with `NSTextStorage`, `NSLayoutManager` and an explicitly sized `NSTextContainer`. It caches measurements using layout-relevant props and width. Rendering is scheduled asynchronously, with host-view updates on the main thread.

Native method hooks in separate production-binary launches found:

| Hooked work, open start through readiness + 150 ms | Initial | Switch |
| --- | ---: | ---: |
| Markdown parses, off main | 20 calls / 0.49 ms | 19 calls / 2.77 ms |
| TextKit ensure-layout, off main | 57 calls / 6.14 ms | 20 calls / 19.53 ms |
| TextKit ensure-layout, main | 81 calls / 4.04 ms | 67 calls / 8.23 ms |
| Native Markdown render requests, main | 10 calls / 0.06 ms | 9 calls / 0.06 ms |

Render-request duration measures scheduling, not the asynchronous render’s completion. Hooked TextKit calls include other text controls, may be nested, and are not an exhaustive partition of renderer time. The 150 ms extension is deliberately included because RN’s lifecycle callback can precede native Markdown presentation. It is a diagnostic observation window, not another definition of visible readiness.

The hooked `ensureLayout` durations can include repeated calls that return from a cache; call counts are not unique messages or full typesetting passes. Native samples locate text layout on the React runtime/JavaScript thread as well as main-thread work. “JavaScript thread” names the thread; the stack doing the text work there is native. This agrees with Fabric’s separation of render, layout/commit, and host mounting. [RN render pipeline](https://reactnative.dev/architecture/render-pipeline), [RN threading model](https://reactnative.dev/architecture/threading-model)

The initial native trace already includes parsing/measurement of early messages. In the top-jump callback interval there are no new hooked Markdown parses; later presentation still performs a little work. Thus the fast top jump benefits from work/caches established during startup. A short readiness callback is not proof that the jump is free: the production captured result is 54 ms.

Existing host startup markers put runtime initialization at roughly 10 ms, including approximately 7.9 ms executing the bundle entry point in the diagnostic runs. These markers do not include every later React render, effect, module access, or native mount. The host window becomes visible before React-root attachment. Saved-document preloading is explicitly disabled whenever the benchmark launch argument is present.

## 5. Same attributed input, different native measurement API

To separate language from API choice, a standalone Swift probe renders each message once, then repeatedly creates fresh measurement objects using the same attributed source and width. One warm-up and five measured repetitions per case:

| Message | Rendered characters | NSTextField intrinsic size | TextKit layout stack | SwiftUI Text via hosting controller |
| --- | ---: | ---: | ---: | ---: |
| First fixture, row 0 | 2,307 | 21.31 ms | 1.02 ms | 23.38 ms |
| First fixture, row 7 | 2,260 | 11.49 ms | 0.91 ms | 14.11 ms |
| Second fixture, row 166 | 19,163 | 104.09 ms | 7.54 ms | 132.50 ms |

Lengths in this probe use `NSAttributedString.length` (UTF-16 units). This includes fresh object/controller construction and first measurement, excludes Markdown parsing, and is not an isolated typesetter-kernel benchmark. Nonetheless, **Swift calling a different Apple text API is already much faster on this input**. RN need not be faster than native code to outperform another native rendering path.

The measured heights differ. For the long message, the three heights were 7,999, 7,834 and 8,020 points respectively. Paragraph spacing, trailing lines and control-specific layout semantics are not identical. Consequently, replacing only the cached height calculation would risk clipping or gaps. A TextKit-based production renderer would need matching rendering/measurement, wrapping, selection and link behavior, plus renewed visual checks. This experiment establishes an API-path difference; it does not certify an interchangeable renderer.

## 6. Discovery: the cost is specific Foundation work, not traversing the disk

Discovery remains unchanged, as requested. A standalone six-pass Swift catalog probe discards the first pass. The catalog includes 110 file candidates and performs 48 source-header checks for unindexed Codex sessions.

| Work | Median accumulated duration |
| --- | ---: |
| Enumerate the three history roots | 0.93 ms |
| Load Codex metadata index | 0.47 ms |
| Construct session IDs | 0.63 ms |
| Read modification metadata | 0.59 ms |
| Format fallback titles | 0.90 ms |
| Subagent header checks, inclusive | 25.39 ms |
| Entire catalog call | 28.81 ms |

A more detailed instrumented repeat breaks down the header checks: approximately 0.44 ms reading data, 0.87 ms decoding UTF-8, **13.26 ms selecting the first line through Swift String splitting**, and **5.89 ms parsing the header JSON with JSONSerialization**. Its full catalog median was 25.44 ms; these detailed measurements are a separate pass, not components to sum into the earlier 28.81 ms total.

The Swift implementation reads up to 64 KiB and converts/splits that String to obtain the first record. RN’s C++ implementation reads the first line and selectively looks for `payload.source.subagent`. That difference explains why blaming Foundation’s directory enumeration or file I/O would be misleading. An idiomatic Swift implementation could inspect the first newline in `Data` before decoding and keep Foundation APIs. That optimization was not applied or benchmarked here, and the catalog’s approximately 23 ms difference is not automatically 23 ms of end-to-end startup improvement because work overlaps.

## 7. What is fair to claim now?

The benchmark is useful and fair as a comparison of these complete, deliberately optimized implementations on this workload. Equivalent document algorithms, verified content and common major layout rules remove the original gross parser mismatch.

It is **not** an isolation of unavoidable framework cost or proof of maximal optimization. This investigation found additional application/framework interactions: opening-animation policy, SwiftUI’s row-structure inference, scheduling of background work, and renderer selection. My earlier “fair comparison” statement should be understood at the application level, not as a guarantee that these remaining choices were equal or optimal.

A defensible thesis is:

> React Native can match or beat native-framework apps when its list and native text-rendering pipeline performs less work or schedules it more effectively. Here, its first-content lead over AppKit is largely presentation policy; its advantage over SwiftUI also involves list construction, task scheduling and a different native text pipeline. These capabilities are available to native applications too.

For further optimization, the highest-confidence next steps are to explicitly choose a common opening-animation policy, start SwiftUI’s parsing worker immediately, and evaluate a native TextKit renderer with matching layout semantics. The fixed-row SwiftUI variant should not ship solely because it reduces body evaluations: our verified recordings expose a top-jump regression alongside startup/switching benefits.

## Evidence, reproduction and limits

- Production baseline: `7de0f85`; all experimental app source copies and bundles live outside the working tree. No history file or RN production source/binary was changed.
- Same two pinned histories and normalized digests: `3a290b9eb53fa834` and `c27e9dc5a848d7f6`.
- Recorded experiments use detector v4, settled 1280-point windows, warm corpus verification and no simultaneous memory sampling or profiler. The AppKit animation pairs ran in the authorized locked console session. The final SwiftUI pairs were repeated under the runner’s unlocked-session requirement; mixed-session earlier SwiftUI batches are excluded. Neither set establishes performance across all session conditions.
- Deep traces are separate unrecorded launches; their lightweight runner did not retain per-launch session state. The first launch of each series is excluded. AppKit’s primary detailed table has two subsequent traces; SwiftUI/RN tables have three. Native sampling is intrusive and serves to identify call paths, not to report latency.
- Inclusive spans overlap; async spans and multi-thread totals cannot be added into a CPU budget. Sub-millisecond figures are useful scale indicators, not precise rankings.
- The sample size is small. Alternating controls improve causal confidence, but do not establish tail latency or universal hardware/OS behavior. Later recording batches drifted relative to the original production batch; compare within a controlled batch.
- Coverage includes launch markers, catalog phases, parser work/dispatch, lazy materialization, Markdown conversion, native text sizing, cell construction, scrolling and final captured presentation. It does not individually time every dyld initializer, every React/Fabric operation, every SwiftUI graph node, GPU execution or WindowServer’s internal scheduling. Unattributed intervals remain unattributed rather than being assigned to a preferred explanation.

[Reproduction instructions and diagnostic sources](experiments/platform-profile/README.md) · [Evidence index](results/2026-09-11-platform-profile/evidence.json) · [AppKit alternating video trials](results/2026-09-11-platform-profile/video-pairs.json) · [SwiftUI verified unlocked alternating trials](results/2026-09-11-platform-profile/video-verified-pairs.json) · [Same-text probe](results/2026-09-11-platform-profile/text-probe.json)
