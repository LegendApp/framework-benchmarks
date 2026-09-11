# Chat History Framework Comparison

Canonical macOS implementations of the same Codex and Claude chat-history browser in Electron, Tauri, Deno Desktop, Flutter, GPUI, SwiftUI, and AppKit. The apps share behavior and benchmark fixtures while using the architecture, parser, list, settings, and packaging conventions natural to each framework.

The production React Native app remains in the sibling `legend-apps` repository.
The benchmark builds it through that repository's export command and includes
it in the default comparison without copying its source here.

## Two workloads

Each technology also has a separate minimal **Hello World** app, so the comparison covers both framework startup overhead and the full chat product. The baselines render the same single label without product dependencies. React Native's baseline is local to this repository; its full product still comes from `legend-apps`.

```sh
bun run benchmark:hello-world
bun run hello-world:electron
```

See the [Hello World benchmark](benchmarks/hello-world/README.md) for all launch commands, methodology, and how to generate a paired Hello World / full product comparison table. The existing `bun run benchmark` command continues to measure the full product.

## Setup

Install [Bun](https://bun.sh), Xcode with command-line tools, CocoaPods,
`ffmpeg`, Rust, Deno, and Flutter. The launcher scripts prefer repository-scoped toolchains under
`.toolchains` and otherwise use tools from `PATH`; they do not modify shell
startup files.

```sh
bun install
```

Run an implementation from the repository root:

```sh
bun run chat-history:electron
bun run chat-history:tauri
bun run chat-history:deno:webview
bun run chat-history:flutter
bun run chat-history:gpui
bun run chat-history:swiftui
bun run chat-history:appkit
```

## Benchmark

The benchmark uses two pinned, old, large transcripts and checks a canonical digest before accepting any result. See [benchmarks/chat-history/README.md](benchmarks/chat-history/README.md) for methodology and prerequisites.
The [Swift/native parity results](benchmarks/chat-history/SWIFT_PARITY_RESULTS.md)
contain the latest native comparison, recordings, and remaining implementation differences.
The [performance analysis](benchmarks/chat-history/PERFORMANCE_ANALYSIS.md) preserves the earlier analysis.

```sh
bun run benchmark:fixtures
bun run benchmark
```

By default the build finds `../legend-apps`, or its `main` worktree. Override
that location when necessary:

```sh
LEGEND_APPS_REPO=/absolute/path/to/legend-apps bun run benchmark
# or
bun run benchmark --react-native-repo /absolute/path/to/legend-apps
```
