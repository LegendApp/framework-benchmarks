# Built app sizes

Measured 2026-09-17T15:34:18.387Z after rebuilding all 19 release apps with `bun run benchmark:build --yes`, then rebuilding both Flutter apps with ARM64-only release settings using `bun run benchmark:build --app flutter --yes`. These are sizes of the current working-tree builds, including external grammar packs. Source changes are uncommitted; exact build timestamps and source revisions are in [the JSON snapshot](BUILD_SIZES.json).

Sizes are MiB (1,048,576 bytes), summing regular files without counting symlinks twice. System-provided frameworks, compressed downloads, build intermediates, and transcript fixtures are excluded. Each app’s full required grammar pack is counted in its combined size, even where other apps can share it. Code signatures and grammar-pack provenance were verified.

This updates sizes only. Startup and memory were not remeasured; the [September 17 performance report](final-2026-09-17/RESULTS.md) retains its original measured-build sizes.

## Chat history

| App | App MiB | Grammar pack MiB | Combined MiB | Executable architecture |
| --- | ---: | ---: | ---: | --- |
| React Native | 17.8 | 22.5 | 40.3 | arm64 |
| Electron | 285.6 | 0.1 | 285.7 | arm64 |
| Tauri | 11.5 | 0.1 | 11.6 | arm64 |
| Deno WebView | 65.8 | 0.1 | 65.9 | arm64 |
| Deno CEF | 307.8 | 0.1 | 307.9 | arm64 |
| Flutter | 21.6 | 0.6 | 22.1 | arm64 |
| GPUI | 9.9 | 0.8 | 10.7 | arm64 |
| SwiftUI | 3.7 | 1.3 | 5.0 | arm64 |
| AppKit | 3.2 | 1.3 | 4.5 | arm64 |

## Hello World

| App | App MiB | Grammar pack MiB | Combined MiB | Executable architecture |
| --- | ---: | ---: | ---: | --- |
| React Native | 7.2 | 0.0 | 7.2 | arm64 |
| Electron | 285.1 | 0.0 | 285.1 | arm64 |
| Tauri | 10.3 | 0.0 | 10.3 | arm64 |
| Deno WebView | 65.0 | 0.0 | 65.0 | arm64 |
| Deno CEF | 307.0 | 0.0 | 307.0 | arm64 |
| Flutter | 17.0 | 0.0 | 17.0 | arm64 |
| GPUI | 5.3 | 0.0 | 5.3 | arm64 |
| SwiftUI | 0.1 | 0.0 | 0.1 | arm64 |
| AppKit | 0.1 | 0.0 | 0.1 | arm64 |

React Native’s chat-history grammar library is external, so app-only size excludes it; combined size includes it. The HighlighterSwift pack includes its existing JavaScript engine and themes as well as grammars. Hello World apps do not require grammar packs.

Both Flutter apps now contain only ARM64 code in the executable, Dart `App.framework`, and `FlutterMacOS.framework`; all six Mach-O binaries were checked. Their app sizes decreased from 42.9 to 21.6 MiB (chat history) and 33.6 to 17.0 MiB (Hello World).

September 18 RN Hello World optimized rebuild: **7,499,962 bytes (7.2 MiB)**,
ARM64 with executable/Hermes symbols stripped, dead-code stripping, ThinLTO,
and `-Oz`. Other rows retain their existing measurement revisions. Legend Shell
is excluded as a duplicate RN host. See
[the optimization audit](../docs/REACT_NATIVE_HELLO_WORLD_OPTIMIZATION.md) for
validation and experimental alternatives. Original cross-framework timings and
memory measurements have not been replaced by the later RN-only runs.

September 18: the shared Legend Apps release builder now uses the same native
compiler optimizations. Chat History measures **18,629,704 app bytes**, plus
**23,617,711 grammar-pack bytes**, totaling **42,247,415 bytes (40.3 MiB)**.
The later RN-only smoke runs do not replace the original performance ranking.
