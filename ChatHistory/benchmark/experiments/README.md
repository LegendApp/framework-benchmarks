# AppKit causal experiments

The layout regression check is versioned. Diagnostic `.patch` files, recordings, and raw traces referenced here are local investigation artifacts and are not included in the production commits.

`appkit-ablation.patch` is a diagnostic patch against the AppKit source used by
this investigation. It is **not applied to the production app**. Apply it in a
separate checkout, build the release app, and run the normal benchmark with
`CHAT_HISTORY_APPKIT_VARIANT` set to one of these values:

- `baseline`: unchanged UI/layout behavior.
- `no-window-animation`: disable the window-opening animation.
- `layer-root`: make the content root layer-backed.
- `main-queue`: deliver callbacks through the main queue instead of common run-loop modes.
- `update-windows`, `force-display`, `flush-transaction`: explicitly submit pending window/layer work after readiness.
- `no-sidebar-scroller`: hide only the sidebar's scrollbar. This tests detector sensitivity to decoration, not a product optimization.
- `immediate-bottom`: scroll immediately after reloading rather than yielding first.
- `bounded-text`: set Markdown labels' `preferredMaxLayoutWidth` to 820, the existing maximum at the tested 1280×720 window size. This is a diagnostic constant, not a responsive-layout fix.

Optional `CHAT_HISTORY_APPKIT_TRACE=/absolute/path.json` records view/layout,
visible-cell creation, attributed-text lengths, and run-loop events. It writes
after twelve seconds. Use a unique path per launch; instrumentation is for
call-path diagnosis and its timings are not production measurements.

Build example, after applying the patch:

```sh
swift build -c release -debug-info-format none --package-path apps/chat-history-appkit
bun apps/chat-history-appkit/scripts/package-benchmark.ts
CHAT_HISTORY_APPKIT_VARIANT=bounded-text bun ChatHistory/benchmark/run.ts --app appkit --warmups 1 --iterations 3 --allow-locked-session --launch-attempts 1
```

The investigation compared old whole-window and corrected transcript-region
scores on the **same captured frames**. Version 3 evidence retains both scores,
the normalized content region, and every source-frame timestamp. A separately
profiled run used `/usr/bin/sample` around startup or the switch; profiler runs
are excluded from production timing summaries.

See [CAUSAL_ANALYSIS.md](../CAUSAL_ANALYSIS.md) for results and limitations.


## Production AppKit resize verification

Run `python3 ChatHistory/benchmark/experiments/verify-appkit-layout.py`. It builds a temporary copy of the current production AppKit source with the entry point replaced by `appkit-layout-check.swift`. The app source and production bundle are not modified. It opens the second pinned fixture and checks widths, text height, and top/bottom visibility at 1040 → 560 → 400 → 1040 point transcript widths. A required parent-width constraint represents the split-view allocation and prevents the standalone test window from sizing itself to intrinsic content. The helper checks AppKit alignment rectangles, which differ from text-field frames because of alignment insets.

## SwiftUI layout diagnostics

`swiftui-layout-probes.patch` is **not applied to production**. Apply it in a separate checkout of the SwiftUI source, then build and package the release app. It adds a forwarding SwiftUI `Layout` around Markdown text when tracing or testing spacing.

- `CHAT_HISTORY_SWIFTUI_TRACE=/absolute/output.json`: time size, spacing, and Markdown conversion calls. Traces flush after content/top readiness. The `initial` phase includes the jump to top; these traces are diagnostic, not production benchmark timings.
- `CHAT_HISTORY_SWIFTUI_VARIANT=probe-spacing`: control that forwards size, placement and preferred spacing, without tracing.
- `CHAT_HISTORY_SWIFTUI_VARIANT=no-text-spacing`: the same layout, returning empty preferred spacing. This isolates the expensive spacing query. It is not a general-purpose production layout replacement.

The patch also preserves unmeasured exploratory `explicit-spacing` and `bounded-text` switches from the investigation. They are not evidence for the reported result; the latter contains fixed diagnostic widths and must not be shipped as a responsive solution.

The spacing comparison ran three paired rounds in alternating order, with no profiler/trace or memory sampler active during recording. Production SwiftUI source and its exact original bundle were restored afterward. See [the results](../RESPONSIVE_LAYOUT_RESULTS.md).
