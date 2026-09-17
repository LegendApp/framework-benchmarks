import AppKit
@testable import ChatHistoryMarkdown
import Testing

@Test @MainActor
func textKitResizesAndReplacesContentWithoutClipping() {
  _ = NSApplication.shared
  let source = RichMarkdownRenderer.render(String(repeating: "A **formatted** paragraph with a [link](https://example.com), followed by enough additional words to wrap several times in a narrow message column.\n\n", count: 100))
  let view = TranscriptTextView()
  view.setContent(source)
  let wide = view.size(fittingWidth: 800)
  let narrow = view.size(fittingWidth: 300)
  #expect(wide.height > 0 && narrow.height > wide.height)
  #expect(view.size(fittingWidth: 800) == wide)
  #expect(view.textStorage?.string == source.string)
  #expect(view.layoutManager?.numberOfGlyphs == source.length)
  let manager = view.layoutManager!
  let finalGlyph = manager.boundingRect(forGlyphRange: NSRange(location: manager.numberOfGlyphs - 1, length: 1), in: view.textContainer!)
  #expect(finalGlyph.maxY <= wide.height + 1)
  view.setContent(RichMarkdownRenderer.render("Short replacement"))
  #expect(view.size(fittingWidth: 800).height < wide.height)
  #expect(view.string == "Short replacement")
  view.expandsToWidth = false
  #expect(view.size(fittingWidth: 800).width < 200)
  view.expandsToWidth = true
  #expect(view.size(fittingWidth: 800).width == 800)
}

@Test @MainActor
func tablesPreserveColumnsAndScrollInsteadOfRewrapping() throws {
  _ = NSApplication.shared
  let source = RichMarkdownRenderer.render("""
    | Name | Description |
    | :--- | ---: |
    | **First** | A [link](https://example.com) followed by a long description that wraps inside its own cell. |
    | Second | Another long description with enough words to wrap independently of the first column. |

    After table.
    """)
  let content = try #require(source.attribute(.transcriptTable, at: 0, effectiveRange: nil) as? TablePaneContent)
  #expect(content.rows.count == 3 && content.columnWidths.count == 2)
  #expect(content.columnWidths.allSatisfy { $0 >= 60 && $0 <= 316 })
  let description = content.rows[1][1]
  let style = try #require(description.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
  #expect(style.alignment == .right)
  #expect(description.attribute(.link, at: (description.string as NSString).range(of: "link").location, effectiveRange: nil) != nil)
  let font = try #require(content.rows[1][0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
  let view = TranscriptTextView(); view.setContent(source)
  let wide = view.size(fittingWidth: 800)
  let narrow = view.size(fittingWidth: 200)
  #expect(wide.height == narrow.height)
  view.frame.size = narrow; view.layoutSubtreeIfNeeded()
  let table = try #require(view.subviews.compactMap { $0 as? TablePaneView }.first)
  #expect(table.frame.width <= 200 && table.documentView!.frame.width > 200)
  #expect(table.frame.maxY < narrow.height)
  #expect(view.string.hasSuffix("After table."))
}

@Test @MainActor
func codePanesScrollWithoutWrappingAndSurviveReuse() throws {
  _ = NSApplication.shared
  let code = String(repeating: "long_code_line_", count: 30)
  let rendered = RichMarkdownRenderer.render("```text\n\n" + code + "\nsecond line\n```")
  let view = TranscriptTextView(); view.setContent(rendered)
  let wide = view.size(fittingWidth: 800)
  view.frame.size = wide; view.layoutSubtreeIfNeeded()
  let pane = try #require(view.subviews.compactMap { $0 as? CodePaneView }.first)
  let scroll = try #require(pane.subviews.compactMap { $0 as? NSScrollView }.first)
  #expect(scroll.documentView!.frame.width > scroll.bounds.width)
  #expect(pane.subviews.contains { ($0 as? NSButton)?.accessibilityLabel() == "Copy code" })
  #expect(pane.frame.maxY <= wide.height + 1)
  let narrow = view.size(fittingWidth: 300)
  view.frame.size = narrow; view.layoutSubtreeIfNeeded()
  #expect(narrow.height == wide.height)
  #expect(pane.frame.width <= 300)
  #expect(wide.height >= 3 * 18 + 39)
  scroll.contentView.scroll(to: NSPoint(x: 200, y: 0))
  #expect(scroll.contentView.bounds.minX > 0)
  // Widths belong to individual views, never to the cached rendering shared by rows.
  let other = TranscriptTextView(); other.setContent(rendered)
  #expect(other.size(fittingWidth: 800).height == wide.height)
  #expect(pane.frame.width <= 300)
  view.setContent(RichMarkdownRenderer.render("Replacement"))
  #expect(!view.subviews.contains { $0 is CodePaneView })
  #expect(view.size(fittingWidth: 300).height < narrow.height)
}

@Test @MainActor
func quotesAndRulesUseLayoutGeometryInsteadOfTextGlyphs() throws {
  _ = NSApplication.shared
  let rendered = RichMarkdownRenderer.render("> A **quote** that wraps over several lines in a sufficiently narrow viewport.\n\n---\n\nAfter")
  #expect(!rendered.string.contains("│") && !rendered.string.contains("────"))
  let style = try #require(rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
  #expect(style.headIndent == 19)
  #expect(rendered.attribute(.transcriptQuotes, at: 0, effectiveRange: nil) != nil)
  let view = TranscriptTextView(); view.setContent(rendered)
  let wide = view.size(fittingWidth: 800)
  #expect(view.size(fittingWidth: 200).height > wide.height)
}

@Test @MainActor
func embeddedContentRemainsCopyableAndNestedBlocksStayInsideTheRow() throws {
  _ = NSApplication.shared
  let rendered = RichMarkdownRenderer.render("""
    > Outer quote
    >
    > - [x] A task
    > - Nested code:
    >
    >   ```swift
    >   let answer = 42
    >   ```

    | Value | Meaning |
    | --- | --- |
    | 42 | **Answer** |
    """)
  let view = TranscriptTextView(); view.setContent(rendered)
  let size = view.size(fittingWidth: 300)
  view.frame.size = size; view.layoutSubtreeIfNeeded()
  for block in view.subviews where block is CodePaneView || block is TablePaneView {
    #expect(block.frame.minX >= 0 && block.frame.maxX <= 301)
    #expect(block.frame.minY >= 0 && block.frame.maxY <= size.height + 1)
  }
  let copied = view.plainText(in: NSRange(location: 0, length: rendered.length))
  #expect(copied.contains("let answer = 42"))
  #expect(copied.contains("42\tAnswer"))
  #expect(!copied.contains("\u{fffc}"))
}
