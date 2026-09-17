# Hello World framework baseline

Latest: [September 16 final results for both workloads](../final-2026-09-16/RESULTS.md), with ten observations per app, built sizes, and the [100-video gallery](results/2026-09-16T21-25-32.060Z/videos.html).

This is the minimal-project counterpart to the [full chat product benchmark](../chat-history/README.md). All ten apps display **Hello, world!** in centered 32-point text on white, in a 1280×720 content window. These are deliberately minimal apps rather than unmodified generator demos.

| Runtime | Baseline source | Runtime dependencies |
| --- | --- | --- |
| React Native macOS | `apps/hello-world-react-native` | React Native macOS 0.81.7, React Native 0.81.6, React 19.1.4; Fabric and Hermes |
| Legend shell | `../legend-apps/apps/hello-world` | Shared React Native shell, React Compiler, and Uniwind; no app-specific native modules |
| Electron | `apps/hello-world-electron` | Electron 44, React and ReactDOM 19.1.4 |
| Tauri | `apps/hello-world-tauri` | Tauri 2.11.5, React and ReactDOM 19.1.4 |
| Deno WebView / CEF | `apps/hello-world-deno` | Installed Deno Desktop toolchain, React and ReactDOM 19.1.4 |
| Flutter | `apps/hello-world-flutter` | Flutter SDK only; no application plugins |
| GPUI | `apps/hello-world-gpui` | GPUI 0.2.2 |
| SwiftUI | `apps/hello-world-swiftui` | System SwiftUI |
| AppKit | `apps/hello-world-appkit` | System AppKit |

The three web hosts bundle the same `packages/hello-world-web` view. The baseline includes React because the corresponding products use React. It does not include LegendList, Markdown, settings, transcript parsers, workers, custom native modules, or history-store access. React Native has a standalone stock macOS host in this repository and does not use the sibling product exporter. The separate Legend shell entry builds the new Hello World app through `legend-apps` infrastructure. Set `LEGEND_APPS_REPO` or pass `--legend-apps-repo` if that repository is not at `../legend-apps`.

See [the September 11 measured results](RESULTS.md) for the complete run and saved video gallery.

Prebuilt apps can be installed with `bun run benchmark:download --suite hello-world --repo OWNER/REPO` from the matching release checkout. See the [release instructions](../../README.md#prebuilt-releases) for prerequisites, version pinning, and publishing.

## Build and open

Install the same prerequisites as the product suite, plus CocoaPods for React Native macOS. Run `bun install` once. Builds use the repository's toolchain wrappers, release configurations, lockfiles, and ad-hoc signatures.

```sh
bun run benchmark:hello-world:build
bun run hello-world:electron
bun run hello-world:tauri
bun run hello-world:deno:webview
bun run hello-world:deno:cef
bun run hello-world:flutter
bun run hello-world:gpui
bun run hello-world:swiftui
bun run hello-world:appkit
bun run hello-world:react-native
bun benchmarks/hello-world/build.ts --app legend-shell --launch
```

Each `hello-world:*` command builds and opens that runtime's release app. To build one without opening it, use `bun run benchmark:hello-world:build --app electron`. Both Deno backends can be selected with `--app deno`. Deno Desktop uses local port 8000, so close another Deno app before launching one. React Native builds its embedded JavaScript bundle with Metro during Xcode's Release build; it needs no running development server.

The batch build command previews its plan and asks for confirmation. Use `--yes` for automation, or `--dry-run` to inspect without building.

Bundles and a build provenance manifest are written to `.build/hello-world-benchmarks/`, separate from product artifacts.

## Measure

```sh
# Build (with confirmation), then measure existing builds.
bun run benchmark:hello-world:build
bun run benchmark:hello-world:run

# Run existing builds or do a short smoke check.
bun run benchmark:hello-world:run
bun run benchmark:hello-world:run --app appkit --warmups 0 --iterations 1
```

The suite requires macOS Screen Recording permission for the existing **Chat History Benchmark Capture** helper, an available display, `ffmpeg`, and `ffprobe`. A scoped `caffeinate` assertion wakes and holds the display for the run, then ends with the runner. It uses the same capture, LaunchServices launch, and window discovery helpers as the full product suite. Keep other applications idle during measurement, especially WebKit clients, since newly created WebKit XPC processes are included in that runtime's memory footprint.

Measurements are:

- **Window open:** launch to the first of three stable recorded frames containing the window.
- **First content:** launch to the first of three consecutive frames in which native-resolution Vision OCR recognizes exactly Hello World (normalized letters, confidence at least 0.8), excluding the title bar. The original downscaled final-image matcher inflated startup times by rejecting already-readable text; the September 10 recordings have been reanalyzed and the original results retained.
- **Settled memory:** a separate production launch without recording, with three physical-footprint samples starting 2.5 seconds after the timing launch's observed content boundary and spaced 200 ms apart. Aggregate RSS is retained as a diagnostic, not the primary memory metric.
- **Bundle size:** logical bytes in the release `.app`, excluding symlinks; system frameworks are not copied into bundles.

Every process is fresh. Warmups are discarded, app order rotates each round, and invalid launches are retried at most twice before the suite fails. The default reference wait is five seconds after window discovery (`--settle-ms` can increase it). The runner rejects missing builds, invalid iteration counts, absent text, failed recordings, and missing footprint samples. It does not accept `--no-video`, since app callbacks do not validate visible Hello World content.

Timestamped JSON and Markdown reports, videos, central text screenshots, OCR results, capture timestamp arrays, and frame sidecars live in ignored `benchmarks/hello-world/results/`. A one-iteration smoke run verifies the pipeline; use the default run for performance conclusions. No transcript fixtures or content-digest configuration is required. Each completed run includes `videos.html` with launch-aligned playback and a selector for every measured recording, plus `videos.md` with direct MP4 links. Capture timestamps and frame-selection metadata are retained beside every video.

## Compare the two workloads

The root `bun run benchmark` now measures existing builds in both workloads; it does not build. See the [command reference](../../README.md#arguments-and-defaults) for filters and defaults. Keep both workloads' reports, then generate a table with paired Hello World / full product numbers:

```sh
bun run benchmark:compare \
  --product benchmarks/chat-history/results/<product-run>.json \
  --hello-world benchmarks/hello-world/results/<baseline-run>/results.json \
  --output comparison.md
```

Use measurements from the same machine and comparable release builds, display conditions, and video mode. The shared columns are startup, settled physical footprint, and bundle size. The product additionally reports discovery, parsing, bridge transfer, top jump, and transcript switch. Differences between the workloads include all product behavior and dependencies; they are not a controlled attribution to any single library or renderer.

Harness regression checks: `bun test benchmarks/hello-world/benchmark.test.ts`.

## Shared window-presentation policy

Both suites now launch apps with process-local `-NSAutomaticWindowAnimationsEnabled NO`. This does not write system or user preferences. See [the fairness report](../chat-history/FAIRNESS_RESULTS.md) for the controlled validation and current results. `CHAT_HISTORY_BENCHMARK_SYSTEM_ANIMATIONS=1` retains system behavior for diagnostic comparisons; result metadata records the policy.

Select several apps with `--app appkit,swiftui,react-native`. The default still selects all ten. `--allow-locked-session` explicitly allows the existing locked-console workflow; timing and companion memory launches both retain their lock state. Such runs describe that session condition, not verified unlocked foreground behavior.

Settled OCR screenshots are extracted by recorded frame index. This avoids EOF-seek failures when a ScreenCaptureKit video has a positive timestamp origin; it does not change the three-frame startup OCR rule.
