# External grammar packs

Chat-history builds install their highlighting resources outside the application
bundles, under `.build/chat-history-benchmarks/grammar-packs/v1/`. Hello World has
no grammar dependency. Build through `bun run benchmark:build` to prepare both
apps and packs; the confirmation preview still applies. A selected technology
builds its required pack automatically.

| Apps | Pack | Representation |
| --- | --- | --- |
| React Native | `tree-sitter` | Signed native grammar library, containing the same parser tables and queries |
| Electron, Tauri, both Deno apps | `highlight-js` | Shared JavaScript language registration module |
| AppKit, SwiftUI | `highlighter-swift` | HighlighterSwift resource bundle with its existing JavaScript and themes |
| GPUI | `syntect` | Serialized two-face syntax definitions |
| Flutter | `dart-highlighting` | Uncompiled Dart-highlighting rule graph with embedded-language dependencies |

For measurement, the runner installs verified packs into a content-addressed
folder under `~/Library/Caches/so.legend.desktop-benchmarks/grammars/`. This keeps
runtime resource loading out of protected Documents checkouts. The installation
is outside timing and is checked against the build manifest. Without an override,
each app resolves the pack beside its `.app`, so the build directory can be
relocated as a unit. `BENCHMARK_GRAMMAR_ROOT` overrides the directory for development and
native tests. The benchmark runner explicitly selects its verified local pack
root rather than inheriting an arbitrary override.

Packs are installed before timing, with no downloads during execution. Loading,
initialization, regex/query compilation, parsing and highlighting still happen
inside the measured app. No parsed transcripts or highlighted tokens are stored in the packs. Missing assets are errors, not a
plain-text performance shortcut. The runner hashes every file and checks the
pack identity recorded with each build before accepting a run.

The results report logical app bytes, required pack bytes, and their sum. Shared
packs are counted in full for each app's standalone installed total; do not add
those totals to estimate disk usage of the entire suite. These resource formats
are engine-specific and do not imply identical binary contents or tokenization.
The web and Swift engines use separate packs because HighlighterSwift has its
own resource-loading format. Its pack retains the original complete resource
bundle (including its JavaScript engine and themes), so that column is the size
of the external highlighting payload, not exclusively parser tables. Combined
installed size includes it all.

Release packaging emits five additional grammar archives, includes them in the
release manifest and checksums, and verifies extraction round trips. Downloading
a subset fetches only its required packs and installs them transactionally with
the apps. Retain the adjacent `grammar-packs` directory when moving apps.

The September 17 measurements and release archives describe the earlier bundled
grammar builds. They are historical evidence, not measurements of these loaders.
New builds and measurements must not be mixed with those artifacts.

See [validation and installed sizes](EXTERNAL_GRAMMARS_VALIDATION.md) for the
rebuilt-app checks and saved video evidence.
