# Rendering-work alignment — September 15, 2026

The completed performance run measured the preceding binaries. This audit found additional concrete differences; its corrections have not yet received a full repeated performance run.

## Corrections

- The four web hosts used Legend List `3.3.5-sparse-layout.94dfeeda.2`, while RN used `3.3.10-sparse-layout.a1fa0789`. The vendored React DOM entrypoint now matches RN's snapshot byte-for-byte. Its generated whitespace is deliberately preserved. This aligns the library revision, not DOM versus Fabric layout internals.
- The web transcript estimated rows at 180 points versus RN's 500. It now uses 500 and explicitly requests the same 250-point draw distance. Estimates influence initial work; they do not force row heights.
- GPUI's configurable overdraw was 600 points; it is now 250, matching RN's requested buffer.
- Code text differed before highlighting/layout: web retained terminal newlines, Flutter removed one, GPUI stripped all trailing whitespace, RN and Swift stripped only terminal newlines. Web, Flutter, and GPUI now match RN/Swift: remove terminal `\n` characters, preserving spaces, tabs and internal blank lines. GPUI also reads only the first word of a fence info string as the language, matching the other parsers.

## What remains different

| Area | Evidence and implication |
| --- | --- |
| Native list preparation | RN/web request 250 points; GPUI now requests 250. Flutter's `scrollable_positioned_list` 0.3.8 clamps its cache to at least two viewport lengths (`_screenScrollCount = 2`); `minCacheExtent` cannot reduce it. AppKit and SwiftUI control native row preparation internally. Equal requested buffers cannot guarantee equal mounted rows or layout passes. |
| Markdown parsers | RN uses md4c, Swift uses swift-markdown, web uses remark, Flutter uses Dart Markdown, and GPUI uses pulldown-cmark. Common tables/lists/quotes/code are supported, but extensions and edge cases are not certified equivalent. RN's parser includes spoiler support; the comparison renderers do not have a standardized spoiler contract. |
| Syntax tokenization | RN uses Tree-sitter; Swift/web highlight.js; Flutter its Dart port; GPUI syntect. Languages and size limits align, but token boundaries, token counts and initialization costs differ. |
| Text/layout engines | DOM, native TextKit, Flutter text and GPUI text have different line breaking, measurement and glyph/layout paths. GPUI's inline-code spans cannot independently set font size within a paragraph. |
| Caching | Row/document caches are local to each implementation. None should eagerly render the full transcript or preload persistent highlighted results, but eviction and reuse differ between list engines. |

The appropriate claim is **comparable visible features with idiomatic engines**, not identical rendering work. Forcing the same highlighted token stream, Markdown tree, mounted row set and layout cache would require a shared rendering pipeline and replacements/adapters for framework list behavior. That would answer a different benchmark question. The current changes do not claim to accomplish it.

## Verification

Focused regression tests cover code whitespace and fence-language parsing; all language fixtures still pass. Web typechecking passes. Runtime checks and artifacts are recorded below after completion.

Validation completed: 15 web tests, 4 Flutter highlighting/normalization tests, 4 GPUI Markdown tests and the Swift code-pane regression pass. All six changed release apps built. Each completed an unlocked recorded bottom/top/switch check and companion memory launch with matching normalized digests; all saved video timestamps align with the source sidecars. The three vendored DOM artifacts match RN's snapshot byte-for-byte.

[Runtime validation results](results/2026-09-15T20-34-46.011Z.json) · [Video validation manifest](results/2026-09-15T20-34-46.011Z.rendering-validation.json)

These six single observations validate transitions only. They are not a repeated performance comparison.
