import AppKit
import ChatHistoryMarkdown
import Testing

@Test @MainActor
func rendersBlockAndInlineMarkdown() {
  let rendered = RichMarkdownRenderer.render(
    """
    # Heading

    A **bold** paragraph with `code` and a [link](https://example.com).

    - first
    - second

    > quoted

    ```swift
    let value = 1
    ```
    """)

  #expect(rendered.string.contains("Heading\n\nA bold paragraph"))
  #expect(rendered.string.contains("• first\n• second"))
  #expect(rendered.string.contains("│ quoted"))
  #expect(rendered.string.contains("let value = 1"))
  #expect(
    rendered.attribute(
      .link, at: (rendered.string as NSString).range(of: "link").location, effectiveRange: nil)
      != nil)
}

@Test @MainActor
func rendersBoundedLocalMarkdownImages() throws {
  let bitmap = try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 1_200,
      pixelsHigh: 900,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0))
  let data = try #require(bitmap.representation(using: .png, properties: [:]))
  let url = FileManager.default.temporaryDirectory.appending(
    path: "legend-markdown-image-\(UUID().uuidString).png")
  defer { try? FileManager.default.removeItem(at: url) }
  try data.write(to: url)

  let rendered = RichMarkdownRenderer.render(
    "![Preview](\(url.path))", imagePolicy: .loadLocal)
  let attachment = try #require(
    rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
  let swiftUIValue = NSAttributedString(AttributedString(rendered))

  #expect(attachment.bounds.width <= 560)
  #expect(attachment.bounds.height <= 440)
  #expect(swiftUIValue.attribute(.attachment, at: 0, effectiveRange: nil) != nil)
  #expect(RichMarkdownRenderer.render("![Preview](\(url.path))").string == "Preview")
  #expect(
    RichMarkdownRenderer.render("![Preview](\(url.path))", imagePolicy: .omit).string
      == "Image or attachment omitted")
}
