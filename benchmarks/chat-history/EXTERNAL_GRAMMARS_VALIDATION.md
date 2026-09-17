# External grammar validation — September 17, 2026

All nine rebuilt chat-history apps completed one recorded benchmark iteration and a separate memory run with external grammar packs. Initial and switched content digests matched across all nine apps (`3a290b9eb53fa834` and `c27e9dc5a848d7f6`).

This is a correctness smoke test (zero warmups, one iteration), not a new final performance ranking. The previous published timing results remain historical. A full controlled benchmark run is still required for updated final numbers.

## Installed size

Logical sizes in MiB (1,048,576 bytes). Shared packs are counted in full for each standalone app.

| App | App bundle | External pack | Combined |
| --- | ---: | ---: | ---: |
| React Native | 19.7 | 22.5 | 42.2 |
| Electron | 285.6 | 0.1 | 285.7 |
| Tauri | 11.5 | 0.1 | 11.6 |
| Deno WebView | 65.8 | 0.1 | 65.9 |
| Deno CEF | 307.8 | 0.1 | 307.9 |
| Flutter | 42.9 | 0.6 | 43.5 |
| GPUI | 9.9 | 0.8 | 10.7 |
| SwiftUI | 3.7 | 1.3 | 5.0 |
| AppKit | 3.2 | 1.3 | 4.5 |

React Native’s smaller app bundle reflects moving grammar code into an external signed library; the combined installation still includes those bytes. HighlighterSwift’s external payload includes its existing JavaScript engine and themes as well as grammars.

## Verification

- All nine release app builds succeeded.
- Web, CLI, release, and grammar-pack tests: 27 passed, including checksums, manifest consistency, cache tampering, and pack selection.
- Grammar archive tests: 7 passed; all five actual pack archives passed extraction round trips.
- Flutter: five syntax/grammar tests passed, including token-tree equivalence against original definitions.
- GPUI and Swift focused syntax tests passed.
- RN external library: all 34 supported aliases produced colored tokens; fallback checks passed.
- TypeScript checks and scoped whitespace checks passed.

## Packaged rendering check

All nine packaged apps also completed a synthetic transcript run with JavaScript in the initial document and Swift, C++, and Ruby in the switched document. Saved final frames show colored code in all nine apps. This verifies external-pack use; it does not establish pixel-identical rendering. Existing differences in token coloring, short-document alignment, and window chrome remain visible.

The synthetic initial transcript contains enough rows to exercise the top-jump transition. A one-row trial did not trigger SwiftUI’s top-jump completion, so it was unsuitable for this scripted check. No production fixtures were modified.

## Evidence

- [Synthetic highlighting video gallery](results/external-grammars-2026-09-17/index.html)
- [Synthetic final-frame contact sheet](results/external-grammars-2026-09-17/contact-sheet.jpg)
- [Recorded smoke results](results/2026-09-17T13-58-25.936Z.md)
- [Raw smoke data](results/2026-09-17T13-58-25.936Z.json)
- [External pack design and usage](EXTERNAL_GRAMMARS.md)

Release packaging and download support is implemented and locally tested. No new GitHub release was published.
