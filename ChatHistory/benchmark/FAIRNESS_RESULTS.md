> **Cross-app fairness audit:** [September 13 audit](ALL_APPS_FAIRNESS_AUDIT.md) identifies unequal document preparation, Flutter viewport ordering, and rendering/style gaps in the broader suite. These historical timings are not an equivalent-work framework ranking.

# Fairness update — September 12, 2026

> Native rendering has changed again since this measurement. See [RN visual alignment](RN_VISUAL_ALIGNMENT.md) for the implementation and pending live visual verification. The timings below belong to the earlier executables.

This update addresses the five concrete issues identified after the shared TextKit integration. The intended standard is competent, idiomatic implementations doing comparable measured work, rather than identical internals or unlimited tuning.

## Changes

1. **SwiftUI list laziness.** Each List element now has a fixed outer view. Row metadata and Markdown are accessed inside that view, allowing List to identify its structure without evaluating every message. A separate diagnostic launch after the lazy-row change and before the table adapter prepared 20 initial Markdown messages and 21 switched messages, rather than the prior 111/126 eager conversions. The exact lookahead remains the framework's own choice.
2. **SwiftUI worker dispatch.** Selecting a document creates the detached parsing task immediately, before scheduling the main-actor task that awaits its result. Generation checks still prevent stale document delivery.
3. **Common presentation policy.** Both benchmark suites use the same launcher, which supplies `-NSAutomaticWindowAnimationsEnabled NO` through the process-local argument domain before application initialization. It does not change user/global defaults, inject code into measured launches, or modify framework binaries. Electron now presents its shell immediately instead of waiting for renderer first paint. Other apps retain their ordinary shell lifecycle. Both timing and capture-disabled memory launches use the policy and retain their console-session state.
4. **Idiomatic Swift discovery.** Catalog discovery slices the first JSONL line in Data before Foundation JSON decoding. It avoids converting and splitting the following transcript text, including a potentially truncated UTF-8 character. Directory traversal and JSONSerialization remain Swift/Foundation; no C++ replacement or fixture-specific shortcut was introduced.
5. **Measured rendering work.** The diagnostic audit found no table-containing messages in the three apps' initial Markdown work, but SwiftUI lookahead encounters one table near the top and six in a message near the switched tail. The native renderer therefore now uses NSTextTable/NSTextTableBlock for independent, bounded cells, retaining inline formatting, links, column alignment, and representative cell padding. It no longer joins table cells into plain text rows. Final viewport inspection also exposed bare native code blocks and extra list-item spacing. Native code now has a language header, padding, border, and unwrapped source in a built-in text block, and tight lists use the same 22-point line spacing. RN now uses the library's existing build-time `enableCodeHighlight: false` setting, scoped to the chat-history release app via its package configuration. Other Legend Shell apps retain their existing settings. The RN top action now scrolls to offset zero with title-bar clearance in content padding; the previous native inset required a negative offset that Legend List clamps away.

## Presentation validation

The preference was observed inside every chat-history host: AppKit, SwiftUI, React Native, Electron, Tauri, Flutter, GPUI, Deno WebView, and Deno CEF. This inspection used separate diagnostic launches; the injected inspector is absent from reported timing and memory launches. A CEF alert helper did not inherit the preference, but the main window-owning host did.

An alternating AppKit control used the same production executable, three trials per condition after one warmup, in on/off/off/on/on/off order. All trials ran in the authorized locked console session. Median settled initial content was **483.3 ms with system animations versus 320.2 ms with animations disabled**. Median internal readiness was 291.6 versus 286.5 ms. Top jump was 68.7 ms in both groups; switching was 76.3 versus 109.7 ms. This controls presentation, not general rendering throughput. It is a small diagnostic comparison, not the final multi-app ranking.

[Animation control JSON and six videos](results/2026-09-12T14-16-42.026Z.json). Do not use that file's mixed-condition aggregate as an app score. Group its iterations by `systemAnimations`; its zero memory values mean unmeasured.

The launch preference is a macOS behavior verified on this machine, not a cross-version API guarantee. Revalidate it with captured presentation when changing OS or framework versions. `CHAT_HISTORY_BENCHMARK_SYSTEM_ANIMATIONS=1` is a diagnostic opt-out and is recorded in result metadata.

## Validation

- 19 Swift tests pass serially, including first-record isolation and real TextKit cell wrapping/alignment/formatting.
- Both production-source layout harnesses pass, including native window/sidebar geometry, resize/revisit behavior, and compact SwiftUI user bubbles.
- All 15 table-containing fixture messages pass wide/narrow TextKit sizing and glyph-bounds checks: 30 configurations.
- TypeScript typechecking and Hello World target-selection tests pass.
- AppKit, SwiftUI, and RN release builds and Electron packaging succeed; both repositories typecheck.
- Separate RN diagnostic launches confirm one foreground color in every measured code block. Switched code reconstruction totaled about 0.17 ms after disabling highlighting, versus 23.3 ms with the previous TypeScript/TSX grammar initialization. These injected diagnostic runs are excluded from benchmark scores.
- The RN smoke recording confirms the first row is fully visible below the title bar after jumping to the top.

[Local audit evidence](results/2026-09-12-fairness-audit/) includes hashed message-to-row matches, preference observations, and validation logs. Message bodies are not included in the audit index. Diagnostic sources and logs are separate from production code and authoritative results.

## Interpretation

The five requested changes are implemented and validated for the RN/AppKit/SwiftUI comparison. List lookahead, text-system scheduling, caches, and framework startup remain different: those are legitimate implementation characteristics to measure. Typography and row spacing are not pixel-identical. Native code keeps full source in text storage and clips overflowing lines; RN also provides horizontal scrolling and a copy button, which these measurements do not exercise. Neither comparison native renderer nor the rebuilt RN app performs syntax highlighting. This benchmark does not certify complete Markdown conformance or establish that every framework has reached its theoretical fastest implementation. The broader runtime table also retains those apps' existing parser and renderer architectures. These are fresh-process launches after warmups, with ordinary OS/file caches; they are not cold-boot measurements. Catalog discovery still reads the live local catalog, while the two transcript fixtures are pinned and hash-verified.

The initial smoke batch `2026-09-12T14-08-11.028Z` ran during diagnostic compilation and before the table change. It is excluded from performance conclusions.

## Final measurements

The first eight-app batch (`2026-09-12T14-19-24.023Z`) preceded the final code-pane, list-spacing, plain-code, and top-origin corrections; it is intermediate evidence, not the final score. The native code and RN smoke batches are visual validation only.

The additional [40-observation batch at 15:05](results/2026-09-12T15-05-32.918Z.md) overlapped external test activity and is retained as a concurrent-load diagnostic. It is excluded from the monitored summary.

### Chat history

**Shared-machine measurements:** competing test/build activity overlapped 18 of 40 timing intervals in the five-second activity log. All observations are retained. These numbers describe this run, not an exclusive-machine or intrinsic framework ranking.

Apple M4, arm64, macOS 26.6.1. One discarded warmup and five measured iterations per app, rotating order, with separate unrecorded memory launches. Times are video-derived p50 milliseconds; memory and logical bundle size are MiB. Discovery is contained within first content. Tauri remains excluded.

| App | Window | Discovery | First content | Jump to top | Switch | Initial MiB | Top MiB | Switched MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AppKit | 250.3 | 16.5 | 360.3 | 71.0 | 83.2 | 41.7 | 47.6 | 49.2 | 2.9 |
| SwiftUI | 311.3 | 21.8 | 566.9 | 157.5 | 326.8 | 53.5 | 57.9 | 66.8 | 3.3 |
| React Native | 260.8 | 8.3 | 444.1 | 33.9 | 135.4 | 53.9 | 58.5 | 59.2 | 19.5 |
| Electron | 577.5 | 32.7 | 1127.3 | 72.2 | 294.3 | 241.6 | 251.2 | 281.8 | 286.1 |
| Flutter | 387.7 | 20.5 | 1160.8 | 79.7 | 520.2 | 88.7 | 94.5 | 106.1 | 42.5 |
| GPUI | 233.4 | 33.0 | 359.7 | 57.0 | 148.3 | 341.2 | 342.1 | 345.1 | 9.1 |
| Deno WebView | 342.6 | 31.0 | 993.0 | 72.5 | 387.1 | 515.9 | 512.3 | 687.8 | 65.8 |
| Deno CEF | 642.3 | 33.5 | 1209.2 | 70.0 | 336.2 | 608.8 | 614.9 | 580.3 | 307.7 |

[Full p50/p90 results and all 40 video links](results/2026-09-12T15-47-27.232Z.md) · [Raw observations and provenance](results/2026-09-12T15-47-27.232Z.json)

### Native stages

P50 milliseconds within the document-open interval. Post-native is calculated per observation before taking its median and includes delivery and viewport work until app-declared readiness. These diagnostic intervals are not additional time to add to the video result.

| App | Initial native | Initial post-native | Switch native | Switch post-native |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 45.8 | 20.0 | 45.7 | 10.6 |
| SwiftUI | 42.5 | 140.3 | 46.7 | 248.6 |
| React Native | 34.6 | 28.9 | 23.3 | 59.3 |

### Reading the result

AppKit's observed first content and switching are faster than RN in this batch; RN is faster than SwiftUI. The old claim that RN starts faster than both native implementations is not supported by these updated medians. AppKit's viewport work after document preparation is small; SwiftUI still has substantially more list/viewport work. Its native document stage is similar to AppKit's, so its remaining delay is not explained by a different Swift parsing algorithm alone.

The five app-level changes remove the identified mismatches in this bounded RN/AppKit/SwiftUI workload. They do not prove all framework costs are isolated or that the wider reference apps have equivalent parser/renderer architectures. A public timing claim needs a repeat with competing test jobs paused or finished; recurring activity prevented an exclusive-machine run here. Near-one-frame differences should not be ranked precisely.

### Evidence and activity

All 40 timing and 40 companion memory launches began unlocked and on-console. Every measured launch completed on its first attempt. All videos have matching decoded frame counts and source timestamps; both normalized digests and both pinned fixture SHA256s match. The changed native and RN source hashes and executable hashes match the recorded builds. No history fixture was edited.

The activity sampler records `ps` every five seconds. The table below flags summed Vitest/esbuild/compiler/build CPU above 30% within an interval plus a five-second margin. Pair intervals conservatively extend to the next timing launch and include postprocessing and memory collection. These are context flags, not causal attribution; ordinary system services also remained active. No flagged observation was removed based on its timing.

| App | Timing intervals flagged | Pair intervals flagged |
| --- | ---: | ---: |
| AppKit | 2/5 | 2/5 |
| SwiftUI | 2/5 | 2/5 |
| React Native | 2/5 | 2/5 |
| Electron | 2/5 | 3/5 |
| Flutter | 3/5 | 3/5 |
| GPUI | 3/5 | 3/5 |
| Deno WebView | 2/5 | 2/5 |
| Deno CEF | 2/5 | 2/5 |

[Activity log](results/2026-09-12-fairness-audit/process-activity.jsonl) · [Verification](results/2026-09-12-fairness-audit/monitored-verification.json) · [Build provenance](results/2026-09-12-fairness-audit/final-build-manifest.json)

### Hello World

The same process-local window policy was rerun across nine baseline apps, including standalone RN and Legend Shell. Five valid measured recordings per app, one warmup per app, and separate memory launches. Tauri was excluded. Times are p50 milliseconds and footprint is MiB.

| App | Window | Greeting | Footprint MiB | Bundle MiB |
| --- | ---: | ---: | ---: | ---: |
| AppKit | 193.4 | 193.4 | 15.5 | 0.1 |
| SwiftUI | 209.2 | 210.8 | 18.3 | 0.1 |
| React Native | 210.5 | 243.8 | 23.4 | 16.3 |
| Legend Shell | 225.9 | 242.6 | 23.8 | 9.3 |
| Electron | 292.3 | 326.8 | 84.1 | 285.1 |
| Flutter | 243.3 | 245.5 | 55.2 | 33.6 |
| GPUI | 211.0 | 227.3 | 56.5 | 5.3 |
| Deno WebView | 376.9 | 411.8 | 82.5 | 65.0 |
| Deno CEF | 375.2 | 380.0 | 202.4 | 307.0 |

[Hello World report and validation](../hello-world/RESULTS.md) · [Launch-aligned video gallery](../hello-world/results/2026-09-12T15-34-04.820Z/videos.html)

All 45 retained videos pass OCR and frame/timestamp verification; all timing and memory launches began unlocked. Seven invalid artifact attempts were retried under the existing policy. The subsequent fix extracts settled screenshots by recorded frame index, avoiding EOF-seek failures with positive video timestamp origins. Its regression test passes; startup OCR analysis is unchanged and retained timings were not recomputed. The activity log saw no competing test/compiler job above 30% during the measured Hello World period, though normal macOS activity remained.
