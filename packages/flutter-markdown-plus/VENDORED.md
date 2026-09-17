# flutter_markdown_plus 1.0.12

Vendored runtime sources from the published pub.dev package, retaining its license and authors. The chat-history app uses this local package through a path dependency.

Local change: `MarkdownBuilder._addBlockChild` does not add paragraph `blockSpacing` between sibling list items. Block/paragraph spacing, the complete Markdown AST traversal, tables, nested structures, inline styles, links, and code builders are retained. Upstream applies the same blockSpacing to every list item and has no separate list-item-spacing setting. This fixes layout without reparsing individual list items or flattening Markdown.

List marker widths also match the transcript policy: an 11-point bullet column, measured ordered markers plus an 8-point gap, and a 22-point checkbox column. Ordered markers remain fully visible.

Additional layout alignment: nested bullet lists retain 24-point indentation with no extra paragraph gap; heading-to-block gaps are 8/6/4 points for h1/h2/h3–h6. The app stretches assistant Markdown to its content width so blockquotes have the same full-width background.
