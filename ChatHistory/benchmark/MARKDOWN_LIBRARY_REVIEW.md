# Markdown library candidate review — September 12, 2026

Historical investigation: subsequent production changes and current measurements are in [TextKit results](TEXTKIT_RESULTS.md). Diagnostic sources and raw evidence linked below are retained locally and are not part of the committed report.

The benchmark needs comparable rendering work, not a complete editor or fully usable product. Missing editing controls, advanced interaction, unexercised math, remote image workflows, or full CommonMark conformance are not automatic disqualifiers. Preserve the exercised content, reasonably match typography and wrapping, render measured viewports fully, and retain representative runtime parsing/layout costs. Minor correctness fixes are acceptable; do not rewrite a dependency to force a favorable result.

## Findings

LiYanan2004/MarkdownView's **MarkdownText** is the strongest off-the-shelf candidate for a SwiftUI integration trial. It builds on macOS, uses RichText's NSTextView/TextKit backend (TextKit 1 by default), keeps complex blocks as hosted attachments instead of flattening them, and exposes separate heading/body fonts. It is not yet validated as equivalent in the benchmark apps. A confirmed ordered-list numbering bug and final typography/attachment layout need attention.

There is **no verified drop-in shared library for pure AppKit and SwiftUI** in this set. LiYanan's Markdown converter and underlying native view are internal; consuming its public view in AppKit requires NSHostingView/NSHostingController. That is a legitimate hybrid app architecture, but would add SwiftUI to what is currently the AppKit comparison. Microsoft has the same public-API distinction. Do not quietly call these pure AppKit renderers merely because NSTextView is underneath.

## Actual workload

Using the current production ChatHistoryCore loader and swift-markdown AST traversal over both pinned histories:

| Feature | Initial history | Switched history |
| --- | ---: | ---: |
| Nonempty user/assistant Markdown rows | 111 | 126 |
| Markdown bytes | 145,774 | 218,629 |
| Headings | 37 | 151 |
| Code blocks | 111 | 25 |
| Tables | 4 | 16 |
| Code blocks nested in lists | 10 | 0 |
| Ordered lists starting above 1 | 4 | 3 |
| Blockquotes | 5 | 0 |

The initial fixture contains two Markdown image nodes in one message; image loading is disabled in the benchmark. Counts cover the complete transcripts, not only the first captured viewport. They establish relevance, not each feature's contribution to startup time. The quote-formatting counter found no Strong/Emphasis/InlineCode/Link within the fixture blockquotes; broader quote limitations therefore are not themselves a demonstrated disadvantage on these fixtures.

## Candidate matrix

| Candidate | Architecture and fit | Assessment |
| --- | --- | --- |
| **LiYanan2004/MarkdownView — MarkdownText** | NSTextView via RichText, default TextKit 1; code/tables/quotes hosted as SwiftUI attachments; separate heading fonts, parsed-content input | **Best SwiftUI trial candidate.** Builds and broad sizing smoke test passes. Confirmed lists starting at 3 become 1; seven fixture lists have non-1 starts. Small fix, not wholesale rejection. No public standalone AppKit Markdown view. |
| LiYanan2004/MarkdownView — MarkdownView | Block-based SwiftUI renderer using the same parser and styling system | Credible SwiftUI alternative, but a different rendering path from MarkdownText. Not separately runtime-tested. |
| **Microsoft/SwiftStreamingMarkdown** | Native TextKit 1 paragraphs plus SwiftUI block composition; per-heading fonts/line-height preference; animation toggle and pre-parsed document input | **Runner-up.** macOS build and 14 sizing checks passed. Source conversion flattens quote text and omits non-inline/non-quote quote children; ordered-list conversion loses starting number. Quote limitations are mostly outside this fixture workload, so not an automatic rejection. AppKit paragraph view is internal; public integration uses SwiftUI hosting. |
| **MarkdownUI (gonzalezreal)** | SwiftUI blocks/Text, GFM parser, themes and pre-parsed MarkdownContent; macOS supported | Credible idiomatic SwiftUI baseline. In maintenance mode. No direct AppKit view. Source-only review; not rejected merely because it uses SwiftUI Text and no performance claim made. |
| **Textual (MarkdownUI successor)** | SwiftUI Text pipeline, Foundation AttributedString parsing, styling and selection; macOS 15+ | Credible current SwiftUI alternative. Requires higher minimum OS than the existing macOS 14 apps, though this benchmark machine supports it. No direct AppKit renderer. Source-only; preserving Text rendering is not itself a fairness defect. |
| **no-problem-dev/swift-markdown-view** | Read-only TextKit 2 rendering separate from editor; custom themes, reusable parsed model | Promising native design, but tables use natural-width tab stops rather than bounded independent cells. Twenty fixture tables make that a material wrapping/layout concern. Attributed builder is package-internal, so its public SwiftUI wrapper is the normal complete entry point. Source-only; table behavior needs a probe before selection. |
| **Lakr233/MarkdownView** | Public AppKit view and SwiftUI wrapper over Litext/CoreText | Architectural fit for both, but actual workload includes the nested-list code it extracts; one title font also fails existing heading distinctions. Fixing these intentionally chosen behaviors exceeds ordinary theming. Parser probe confirmed transformations; prior detailed review below. |
| **HumanInterfaceDesign/MarkdownView** | Related native/CoreText design with extra diff/highlighting support | Retains list extraction, quote flattening, and ignored heading level in reviewed source. Same relevant concerns as Lakr; extra features provide no reason to choose it for this workload. Source-only. |
| **nodes-app/swift-markdown-engine** | AppKit TextKit 2 source editor, SwiftUI bridge, editable flag | Editing is not required. Source storage/marker hiding and editor styling do different work than rendering message bodies. Disabling editing alone is not proof of a like-for-like display pipeline. Source-only; not selected for this rendering benchmark. |
| **Software Mansion enriched-markdown-ios** | Standalone Swift renderer from the related ecosystem | Current package declares iOS and imports UIKit in its implementation. No off-the-shelf macOS support; porting is beyond ordinary integration. Existing RN macOS renderer is a different packaged integration. |

MarkdownUI search-result mirrors/forks were not counted as independent engines. The upstream and its successor were inspected. This is a review of the candidates surfaced in this investigation, not a claim to exhaust every Markdown project on GitHub.

## Executed validation

- Compiled workload scanner against the current production document loader; exported message text only to /tmp, not this repository.
- Built unmodified LiYanan MarkdownView and Microsoft SwiftStreamingMarkdown library targets in disposable checkouts on macOS.
- LiYanan MarkdownText: 236 fixture messages (one image-containing message excluded) plus four synthetic inputs, at 886 and 400 pt: **480/480 positive finite measured heights**. This does not by itself prove all content is visible or styled correctly.
- LiYanan synthetic inspection: H1/H2 backing font sizes accept 22/19 pt; nested-code attachment stays between preceding and following text. Ordered list `3. third / 4. fourth` becomes `1. third / 2. fourth`.
- Microsoft: four synthetic cases plus three long fixture messages, at two widths: **14/14 positive finite measured heights**. Animation explicitly disabled; pre-parsed input used. Default typography differs from the production benchmark and was not compared for speed.
- Earlier Lakr parser probe confirmed five synthetic cases, detailed below.

The other candidates received source/API review, not full builds, conformance tests, or timing runs. No app source/dependency changed. No startup, memory, video, or end-to-end fairness claim follows from these checks.

[Source pins, probe code, and non-content outputs](experiments/markdown-library-review/README.md) are retained locally in the repository. Each pinned revision's repository URL is in [revisions.json](experiments/markdown-library-review/revisions.json).

## Recommendation for this benchmark

Do not require one shared third-party dependency at the cost of changing the platform under test. Use **MarkdownText as the leading SwiftUI library trial**. For AppKit, first test the ordinary NSTextView/TextKit presentation adapter around the existing parsed/attributed Markdown pipeline; that is integration with a native control, not building a complete Markdown editor or a new text engine. Check the same exercised tables, code, typography, and captured viewports before accepting either. If choosing a shared SwiftUI-backed library for both instead, label AppKit as an AppKit shell with SwiftUI Markdown content.

This relaxed benchmark scope permits small fixes and omits unused product features. It does not permit deleting rendered content or calling a different platform stack the same comparison.

---

## Earlier Lakr-specific investigation

Decision: reject Lakr233/MarkdownView as a drop-in replacement for this comparison. Its native AppKit/SwiftUI architecture is suitable, but its deliberate Markdown transformations and typography API do not meet the existing behavior contract. No production dependency or app source was changed.

Reviewed upstream revision: `4abc4817fa5211f05e25fbf7a6295fb8e9fcfd90`.

## Evidence

Built the unmodified MarkdownParser sources in an isolated executable with the existing local swift-cmark checkout (`924936d0427cb25a61169739a7660230bffa6ea6`). Five synthetic cases compiled and ran successfully:

| Input | Observed parser output |
| --- | --- |
| Fenced Swift code inside a quote | Ordinary paragraph; code-block identity and language removed |
| Bullet list inside a quote | Separate paragraphs without list structure |
| Nested quote | One quote containing both paragraphs; nested depth removed |
| Ordered item with code followed by a continuation paragraph | Item contains step and continuation, followed by a top-level code block; continuation moves before code |
| H1 and H2 | Parser retains levels; renderer ignores them, as confirmed separately in source |

These are structural differences, not merely antialiasing or minor spacing differences. The list example also changes reading order.

Source findings:

- `MarkdownParser+SpecializeContext.swift` explicitly extracts complex list children and flattens quote contents. There is no public parser option to disable this transformation.
- `BlockProcessor.processHeading(level:contents:)` ignores its level parameter and uses one `theme.fonts.title`. Our RN app explicitly uses H1 22/28 and H2 19/25 font size/line height.
- Paragraph/list/quote rendering hardcodes lineSpacing = 4; the public theme lacks matching per-element exact line-height controls.
- Inline images become source-URL links. This is an additional integration concern, not a demonstrated benchmark-image mismatch: the benchmark disables image loading, and RN renders attachment images separately.
- AppKit and SwiftUI wrappers exist, including synchronous proposed-width sizing. This is a positive architectural fit, but UI sizing/selection correctness was not runtime-tested after the semantic gate failed.

Pinned source references:

- [Parser transformations](https://github.com/Lakr233/MarkdownView/blob/4abc4817fa5211f05e25fbf7a6295fb8e9fcfd90/Sources/MarkdownParser/MarkdownParser/MarkdownParser%2BSpecializeContext.swift)
- [Heading and paragraph rendering](https://github.com/Lakr233/MarkdownView/blob/4abc4817fa5211f05e25fbf7a6295fb8e9fcfd90/Sources/MarkdownView/MarkdownTextBuilder/BlockProcessor.swift)
- [Public theme](https://github.com/Lakr233/MarkdownView/blob/4abc4817fa5211f05e25fbf7a6295fb8e9fcfd90/Sources/MarkdownView/MarkdownTheme/MarkdownTheme.swift)

## Scope and conclusion

This was a source review and executable parser probe, not a full UI build, corpus-wide conformance run, or performance comparison. It does not establish how frequently the structural cases occur in the pinned histories. The heading-style mismatch alone prevents matching our current typography through normal public configuration.

Do not fork this library into a bespoke benchmark renderer to overcome its intentional design choices. Evaluate a renderer that preserves Markdown structure and exposes the required typography first. No replacement candidate has passed that evaluation yet.
