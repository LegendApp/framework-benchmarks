import AppKit
import ChatHistoryMarkdown
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
