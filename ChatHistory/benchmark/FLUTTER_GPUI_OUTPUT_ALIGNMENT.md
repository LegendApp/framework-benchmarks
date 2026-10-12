# Flutter and GPUI output alignment — September 16, 2026

Both applications retain full Markdown parsing and their real syntax highlighters. This change fixes output geometry; it does not skip parsing, flatten formatted text, truncate code, disable highlighting, or change list prefetch/cache settings.

## Corrected differences

- Both previously inserted a 16-point paragraph gap after each list item, producing roughly 38-point rows instead of RN's 22-point rows. Adjacent items now share the 22-point line height; block spacing after a list remains 16 points.
- Bullet indentation is now 11 points (3-point marker allocation plus 8-point gap), with 6-point painted bullets. Ordered markers retain measured width and task markers retain their own width.
- Flutter nested bullet lists now indent by 24 points and no longer acquire an extra paragraph gap. Heading-to-next-block spacing is 8/6/4 points for h1/h2/h3–h6.
- Flutter assistant Markdown fills the content column, including the blockquote background. Short user bubbles continue to fit their contents.
- GPUI code panes now include the header divider present in RN and the other renderers.

Flutter's upstream library has one `blockSpacing` applied to list items as well as paragraphs. The app uses a documented, local copy of flutter_markdown_plus 1.0.12 with a narrow layout patch. This preserves its entire Markdown visitor, table layout, links, inline styles, and code-builder integration, without separately reparsing list items. See [vendoring notes](../../packages/flutter-markdown-plus/VENDORED.md).

## Parsing and highlighting verification

GPUI still uses pulldown-cmark and syntect/two-face; Flutter still uses markdown/flutter_markdown_plus and highlighting. Both parse the complete Markdown source for prepared rows and highlight declared code languages under the same language/size policy as RN. Unsupported languages and blocks exceeding the shared limit retain their full text with the common plain-code fallback. Parsing/highlighting remains viewport-driven, as in RN, rather than eagerly processing every message.

- GPUI: 8 parser/highlighter tests passed, covering nested lists, tables, tasks, inline formatting, source preservation, and all shared language fixtures.
- Flutter: 6 layout/highlighter tests passed, including measured 22-point list row spacing, 24-point nested indentation, heading gaps, complete code content, and colored spans.
- Both release builds succeeded.
- Both final production bundles completed an unlocked, recorded initial/top/switch check and separate memory launch. Initial digest `3a290b9eb53fa834` and switched digest `c27e9dc5a848d7f6` match the other apps. Video/source timestamps align within 0.001 ms.
- Additional isolated synthetic histories visibly exercise headings, bold/italic/strike, links, nested lists, a blockquote, a table, and JavaScript/Swift/C++/Ruby code. Screenshots show actual syntax colors. These are correctness probes, not performance measurements.

## Evidence

- [Final history validation run](results/2026-09-17T06-53-40.159Z.json) and [video/transition validation](results/layout-alignment-2026-09-16/validation.json).
- Dense lists: [Flutter](results/layout-alignment-2026-09-16/flutter-top.png), [GPUI](results/layout-alignment-2026-09-16/gpui-top.png), [RN reference](../final-2026-09-16/visual/top-react-native.png).
- Switched history: [Flutter](results/layout-alignment-2026-09-16/flutter-switch.png), [GPUI](results/layout-alignment-2026-09-16/gpui-switch.png), [RN reference](../final-2026-09-16/visual/switch-react-native.png).
- Rich Markdown: [Flutter](results/layout-alignment-2026-09-16/flutter-rich-initial.png), [GPUI](results/layout-alignment-2026-09-16/gpui-rich-initial.png).
- Highlighted code: [Flutter](results/layout-alignment-2026-09-16/flutter-rich-switch.png), [GPUI](results/layout-alignment-2026-09-16/gpui-rich-switch.png).
- [Repeatable rich-content probe](experiments/verify-flutter-gpui-rendering.py).

## Scope and performance

The conspicuous list-density difference is removed: the measured top views now show the same list items at comparable positions, and the switched history matches RN's compact list layout. This removes that potential source of unequal visible work. It does not establish pixel identity across libraries: font metrics, syntax token categories, chrome, and GPUI's existing single-size inline-text constraint remain (inline code shares the paragraph's 15-point size instead of RN's 13-point size). The probe does not certify every Markdown extension or every nested structure.

The September 16 repeated performance table describes the previous Flutter/GPUI binaries. These single-launch checks validate rendering and transitions only; do not substitute their timings into the repeated ranking. Rerun the affected apps before publishing updated performance numbers. Hello World is unchanged.
