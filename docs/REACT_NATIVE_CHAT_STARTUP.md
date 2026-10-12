# React Native Chat History startup work — September 18, 2026

## Change under test

Catalog discovery previously began in the first React passive effect (`ChatHistoryWindow`), followed by selected-document opening in an observable effect. The normal saved-selection path already began native parsing at `NSApplicationWillFinishLaunching`, but first launches and benchmark launches waited for React.

The uncommitted candidate extends that existing native startup hook. A worker discovers the same catalog, resolves the initial ID, and starts the same parser before React adoption. `getRecentChats` adopts the catalog future once; `openChat` adopts the prepared document through the existing cancellation/ownership mechanism. Subsequent refreshes and opens remain fresh operations. Saved-selection parsing is not duplicated. Normal missing selections fall back to newest, while missing benchmark IDs do not silently substitute another conversation.

All work begins after process launch. Benchmark mode still discovers its pinned ID through the full catalog; it receives no fixture-path shortcut, persisted parsed document, pre-highlighted content, or prelaunch work. Native parse stages still include work completed before JavaScript adopts the result. The existing JS `discoveryMs` measures adoption-call latency, so after this change it must not be interpreted as total native discovery cost.

## First-content audit

The app's two-frame wait reports readiness and schedules later benchmark phases; it does not gate rendering. It remains unchanged. Transcript rows already have an initial list-size estimate and bottom positioning. Image-dimension effects do not run in the image-disabled benchmark. Composer cleanup and final window options do not explain the catalog/document dependency chain; neither was changed.

## Baseline and validation

A fresh baseline release was built before edits. Two warmups and three measured video launches, with companion memory launches, produced median first content **387.8 ms**, window **220.6 ms**, jump **43.8 ms**, and switch **191.0 ms**. Initial native document work was **41.6 ms**. This is an exploratory baseline, not a new cross-framework ranking.

[Baseline results](../ChatHistory/benchmark/results/2026-09-18T22-45-40.094Z.json) and [report/videos](../ChatHistory/benchmark/results/2026-09-18T22-45-40.094Z.md). A copy of the original bundle and manifest is retained under `.build/rn-startup-audit/` for controlled comparison.

Native fixture/parser and image tests pass, including startup single-use adoption, cancellation, missing target, older selected conversation, normal newest fallback, avoidance of duplicate saved-selection loading, and fresh catalog refresh. The recent-20-chat schema audit also passes. The macOS launch hook passes a standalone Objective-C++ syntax compile.

**Candidate release build now passes (September 19).** The earlier Bun hang occurred before script execution, with the main thread blocked in macOS `openat`. It no longer reproduces under either the direct invocation or the same build wrapper. Privacy attribution logs do not establish a cause; no permission change or Bun reinstall was needed.

The resumed build exposed a separate Babel configuration error: the shared shell unconditionally resolved Slides' `react-native-worklets/plugin`, including for Chat History. Slides now owns the plugin in `apps/slides/babel.config.cjs`; the shared shell loads optional app extensions generically, and the app ID participates in Babel's cache key. Chat History and Hello World configuration checks pass without Slides dependencies; Slides still requires its plugin. The full Chat History release build and export succeeded. Two warmups and three measured video runs plus companion memory launches completed successfully, with no discarded attempts and matching initial/switch parser digests. [Candidate report and videos](../ChatHistory/benchmark/results/2026-09-19T07-12-52.252Z.md): median window 266.3 ms, first content 428.1 ms, jump 36.8 ms, switch 180.9 ms; physical footprint 53.1 / 57.6 / 65.0 MiB.

This does **not** establish a startup improvement over the previous day's 387.8 ms baseline. Window opening also shifted by roughly 46 ms, and the generated JavaScript bundle hashes differ, so this is not an isolated same-session A/B comparison. Keep the candidate uncommitted pending controlled comparison; these results do not replace the published framework ranking.

## Completed same-session measurement

The [September 19 comparison and updated full table](REACT_NATIVE_BENCHMARK_RESULTS.md) contain ten scored launches of each saved build from fixed paths, with two discarded warmups per build and separate memory launches. Median first content was 398.3 ms baseline versus 393.2 ms candidate, a 5.1 ms / 1.3% difference. Samples overlap; internal readiness did not improve. This does not demonstrate a meaningful startup win. All scored content/session/video checks passed. The candidate remains uncommitted; deeper profiling is needed before claiming this scheduling change helps. Other frameworks were not remeasured.
