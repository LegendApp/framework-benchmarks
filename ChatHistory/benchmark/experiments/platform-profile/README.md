# Platform timing investigation

These are **diagnostic sources**, not production changes. See [the report](../../PLATFORM_TIMING_REPORT.md) and [local evidence index](../../results/2026-09-11-platform-profile/evidence.json).

The patch captures instrumentation against commit `7de0f85`. It adds monotonic wall-time spans and call counts around native file work, scheduling boundaries, Markdown conversion, row creation and text measurement. Logging buffers events under a lock and writes snapshots later. Sampling and tracing are intentionally separate from authoritative recorded timing.

## Prepare and build

Run from the comparison repository. Choose a fresh scratch directory; preparation refuses to overwrite an existing source tree.

```sh
export CHAT_PLATFORM_PROFILE_ROOT=/tmp/chat-platform-profile-repro
python3 ChatHistory/benchmark/experiments/platform-profile/prepare.py
swift build -c release -debug-info-format none --package-path "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/chat-history-appkit"
swift build -c release -debug-info-format none --package-path "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/chat-history-swiftui"
cp "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/chat-history-swiftui/.build/release/ChatHistorySwiftUI" "$CHAT_PLATFORM_PROFILE_ROOT/SwiftUI-baseline"
python3 ChatHistory/benchmark/experiments/platform-profile/run.py --rounds 4
```

The runner copies existing production bundles into scratch space and replaces only their executables with diagnostic builds. RN runs its unchanged production bundle. It launches the existing pinned benchmark workload, retains events and traces, and terminates only the PIDs it launched. The initial pass is a warm-up and must be excluded. No production bundle is overwritten.

`--baseline-binary` selects the saved SwiftUI baseline after building a variant. `--sample --rounds 1 --variant sampled-baseline --baseline-binary` records one-second, one-millisecond-interval native samples around startup, top jump and switching. Sampling can substantially distort durations; use it for call paths only.

The runner permits the locked console session used for the investigation. It does not establish foreground performance. The production video runner verifies fixture hashes; the lightweight trace runner assumes the unchanged local manifest and uses the first full launch to warm the workload.

## Variants

Apply patches only in the prepared source tree and rebuild SwiftUI:

- `swiftui-static-row.patch`: fixed outer row structure, retaining the same message components.
- `swiftui-early-worker.patch`: create the parser worker before scheduling the main-actor awaiting task. Apply to the instrumented baseline, not on top of unrelated experiments.
- AppKit already has the `CHAT_PLATFORM_VARIANT=no-window-animation` diagnostic toggle in its instrumentation patch; the executable is identical in both conditions.

`run.py --variant NAME` selects the output name and AppKit runtime toggle. For SwiftUI, **the source/binary must first be changed and rebuilt**; naming a variant alone does not apply a patch.

The detailed report uses the original baseline traces, the fixed-row traces and the early-worker traces as separate series. Do not combine their medians into one additive timeline.

## RN native hooks

```sh
clang++ -std=c++17 -dynamiclib -fobjc-arc -framework AppKit ChatHistory/benchmark/experiments/platform-profile/NativeTrace.mm -o "$CHAT_PLATFORM_PROFILE_ROOT/NativeTrace.dylib"
codesign --force --sign - "$CHAT_PLATFORM_PROFILE_ROOT/NativeTrace.dylib"
python3 ChatHistory/benchmark/experiments/platform-profile/run.py --apps react-native --rounds 4 --variant segmented-hooks --native-trace
```

The injected library restricts itself to the `Legend Chat History` process. It hooks the actual segmented GitHub Markdown component, its parser, and `NSLayoutManager`. Records contain timings, character lengths and thread identifiers, not message contents. The launch helper is not instrumented. An app-side readiness event can precede native Markdown presentation: the report separately analyzes the interval ending 150 ms after that callback. Hooks are partial coverage and durations can nest.

## Standalone probes

Copy `catalog-probe` and `text-probe` into `$CHAT_PLATFORM_PROFILE_ROOT/source/apps/`, then build with the same release command. Their manifests resolve the instrumented core relative to that location.

```sh
cp -R ChatHistory/benchmark/experiments/platform-profile/catalog-probe "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/"
cp -R ChatHistory/benchmark/experiments/platform-profile/text-probe "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/"
swift build -c release -debug-info-format none --package-path "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/catalog-probe"
CHAT_PLATFORM_TRACE="$CHAT_PLATFORM_PROFILE_ROOT/results/catalog-detail.trace.json" "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/catalog-probe/.build/release/CatalogProbe"
swift build -c release -debug-info-format none --package-path "$CHAT_PLATFORM_PROFILE_ROOT/source/apps/text-probe"
"$CHAT_PLATFORM_PROFILE_ROOT/source/apps/text-probe/.build/release/TextProbe" ChatHistory/benchmark/fixtures.local.json > "$CHAT_PLATFORM_PROFILE_ROOT/results/text-probe.json"
```

The text probe excludes Markdown conversion, creates fresh measurement objects, and retains measured sizes as well as timings. It intentionally exposes height differences; it does not assert renderer equivalence. The catalog probe’s round 0 is discarded.

## Recorded controls

`prepare-video-runner.py` adapts the existing runner in `/tmp/chat-native-benchmark-runner/` to target disposable AppKit/SwiftUI bundles. It disables companion memory sampling; zero-valued memory fields in these timing-only outputs mean **not measured**. The variant name and executable hash are retained in the trial index.

`video-pairs.py` ran AppKit baseline/no-animation and the first trace-capable SwiftUI fixed-row experiment, three trials per condition in alternating pair order. It expects the current scratch SwiftUI executable to be the fixed-row variant and the saved `SwiftUI-baseline` binary to exist.

`prepare-clean-swiftui.py` creates an uninstrumented fixed-row SwiftUI package against the production core and copies the production baseline executable. Build its `swiftui-clean` package, then run `video-verified-pairs.py` for the final SwiftUI controls. This final runner omits `--allow-locked-session`, so the underlying runner rejects locked launches and any lock transition during observation. `video-clean-pairs.py` is retained as an exploratory predecessor. Both scripts use the prepared video runner and already-created disposable bundles.

Keep capture awake for the entire recorded run using the [macOS capture setup helper](/Users/jay/.codex/skills/macos-screen-capture-setup/scripts/prepare-macos-capture.sh). Run one capture series at a time, with no native samples, diagnostic trace environment, builds, or footprint sampling active. Inspect accepted frames and verify digests and settled window dimensions.

## Evidence interpretation

- `video-pairs.json`: final AppKit controls; its SwiftUI rows are exploratory.
- `video-clean-pairs.json`: mixed-session exploratory SwiftUI controls; excluded.
- `video-verified-pairs.json`: final uninstrumented SwiftUI controls, all passing the unlocked-session requirement.
- `*-baseline-1` and the first trial of each trace series: warm-up diagnostics, excluded.
- `*-sample-*`: intrusive call-stack evidence, excluded from latency summaries.
- RN `baseline-native` and `hooks-v2`: exploratory hook coverage. Use `segmented-hooks` for the report’s final native method table.
- `summarize.py`: aggregate trace spans up to lifecycle readiness; it does not include RN’s additional 150 ms presentation window or pretend nested spans are additive.
- Raw logs, traces, recordings, binaries and QA images remain ignored/local. The reproducible diagnostic sources and report are versionable.
