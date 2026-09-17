# Syntax highlighting alignment — September 13, 2026

The preceding all-app alignment was checkpointed in `a96c3d3`. Syntax highlighting
is now enabled in all nine chat-history targets. Hello World has no Markdown/code
content and is unaffected.

| Targets | Highlighting implementation |
| --- | --- |
| React Native | Enriched Markdown 1.0.2, native Tree-sitter; explicitly includes all 19 supported grammars |
| AppKit, SwiftUI | HighlighterSwift 3.1.0 / highlight.js 11.11.1, applied to native attributed strings |
| Electron, Tauri, Deno WebView, Deno CEF | Shared highlight.js 11.11.1 renderer |
| Flutter | `highlighting` 0.9.0+11.8.0, a Dart highlight.js port, rendered as TextSpans |
| GPUI | syntect 5.3.0 with two-face 0.5.2 grammars, rendered as native text runs |

## Common policy

- Highlight declared fence languages; do not run language auto-detection.
- Cover Bash, C, C++, C#, CSS, Go, HTML, Java, JavaScript/JSX, JSON, Markdown,
  PHP, Python, Ruby, Rust, Swift, TypeScript, TSX and YAML, including the same
  34 language names/aliases. `syntax-highlighting-policy.json` records the mapping.
- Match RN's whole-block fallback at more than 51,200 UTF-8 bytes or 2,000 lines.
  Unknown/unlabelled fences remain plain text. Fallback never truncates the code.
- Apply foreground colors to code, preserving the established font, line height,
  horizontal scrolling and copy behavior. Use the GitHub-dark syntax color family
  on the existing dark code background in both app appearances.
- Highlight as visible Markdown rows are rendered. No eager highlighting pass over
  the full history, no persistent warm highlighting cache, and no delayed coloring
  after the content-ready boundary. Existing row/view caches remain in use.

The engines are normal reusable libraries for their host language. They do not
produce identical syntax trees or token classifications. For example, an
identifier may be orange in RN and inherit the foreground in another renderer.
This is feature parity for an application benchmark, not an isolated comparison
of an identical highlighting algorithm. Existing layout differences documented
in the alignment audit remain; the screenshots are not pixel-identical.

## RN and Swift fixes required

The RN benchmark export previously forced `enableCodeHighlight: false`. It now
forces it on while retaining its isolated build workspace. The benchmark-only configuration in `apps/chat-history/scripts/benchmark-markdown.json`
selects the five grammars omitted from the dependency's defaults (C++, C#, PHP,
Ruby and Swift). Production does not inherit this language override. Its current
Enriched Markdown engine uses compiled grammars; runtime grammar downloads remain
a separate production capability to implement, rather than a consequence of removing
the benchmark override. The existing Enriched Markdown dependency patch now maps the
bundled Markdown grammar's legacy `text.*` captures to colors; otherwise its
headings and links were parsed without receiving syntax colors.

HighlighterSwift is vendored at upstream commit
`fe7aae9c9b31d3b296fd3d2dd575e1a207bb29e0`, with its original engine, Swift sources,
resource inventory and licenses. One resource-location patch lets signed macOS
apps find the resource bundle in `Contents/Resources`; SwiftPM's CLI-generated
lookup otherwise falls back to the original build directory. Both native
exporters copy the resource bundles into the signed app. See the vendor README.

Benchmark-only fixture-home overrides let RN, AppKit and SwiftUI use the same
isolated synthetic catalog as the other targets. Normal app discovery is unchanged;
no real history file was modified for these checks.

## Validation and saved comparisons

- 53 comparison tests pass: web 14, Swift 23, Flutter 10, GPUI 6.
- RN release-profile tests: 4 pass, including production/benchmark grammar isolation; native chat-history tests pass.
- `verify-rn-highlighting.py` compiles the actual RN dependency's native highlighter
  and verifies colored output for all 34 language names/aliases, plus plain fallback.
- Shared language fixtures test token output and complete Unicode source retention
  across the other four renderer implementations. Tests cover unknown languages,
  oversized UTF-8 content and line limits; Flutter also checks nested function scopes.
- TypeScript checks, Flutter analysis and both Deno entry-point checks pass.
- All nine release app bundles build. Saved visual QA uses the same synthetic
  two-conversation catalog with a TypeScript fence, nested Markdown, tables and a
  long second conversation. The content viewport is 1280×720; Deno additionally
  retains its 28-point native title bar.

[Open the screenshot/video viewer](results/2026-09-13-syntax-highlighting/index.html).
The final directory contains nine videos, timestamp sidecars and 27 screenshots
(initial content, top of first conversation, second conversation).
`SYNTAX_HIGHLIGHTING.sources.json` records validation evidence and source/binary hashes.

These are correctness recordings, not scored timing or memory measurements.
Previous performance tables measured the earlier rendering workload and must be
rerun across **all** targets before comparing highlighted startup or memory use.
No new performance ranking is claimed here.

## Library sources

- [Enriched Markdown](https://github.com/software-mansion/enriched-markdown)
- [highlight.js API](https://highlightjs.readthedocs.io/en/latest/api.html)
- [HighlighterSwift 3.1.0](https://github.com/smittytone/HighlighterSwift/tree/3.1.0)
- [Dart highlighting](https://pub.dev/packages/highlighting)
- [syntect](https://github.com/trishume/syntect)
- [two-face grammar inventory](https://docs.rs/two-face/latest/two_face/)
