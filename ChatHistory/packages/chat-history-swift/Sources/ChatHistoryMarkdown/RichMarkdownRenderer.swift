import AppKit
import Markdown

public enum RichMarkdownImagePolicy: Equatable, Sendable {
  case altText
  case loadLocal
  case omit
}

@MainActor
public enum RichMarkdownRenderer {
  public static func render(
    _ source: String,
    imagePolicy: RichMarkdownImagePolicy = .altText
  ) -> NSAttributedString {
    Renderer(imagePolicy: imagePolicy).render(Document(parsing: source))
  }
}

@MainActor
private struct Renderer {
  private let baseFont = NSFont.systemFont(ofSize: 15)
  private let baseAttributes: [NSAttributedString.Key: Any]
  private let imagePolicy: RichMarkdownImagePolicy

  init(imagePolicy: RichMarkdownImagePolicy) {
    self.imagePolicy = imagePolicy
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = 22
    paragraph.maximumLineHeight = 22
    baseAttributes = [
      .font: baseFont,
      .foregroundColor: TranscriptColors.foreground,
      .paragraphStyle: paragraph,
    ]
  }

  func render(_ document: Document) -> NSAttributedString {
    renderBlockChildren(document)
  }

  private func renderBlock(_ markup: Markup) -> NSAttributedString {
    switch markup {
    case let heading as Heading:
      let result = renderInlineChildren(heading)
      let sizes: [CGFloat] = [22, 19, 20, 18, 16, 14]
      let heights: [CGFloat] = [28, 25, 28, 26, 24, 22]
      let style = NSMutableParagraphStyle()
      style.minimumLineHeight = heights[min(max(heading.level - 1, 0), 5)]
      style.maximumLineHeight = style.minimumLineHeight
      let size = sizes[min(max(heading.level - 1, 0), sizes.count - 1)]
      result.addAttributes(
        [.font: NSFont.systemFont(ofSize: size, weight: .bold), .paragraphStyle: style],
        range: result.fullRange)
      return result
    case let paragraph as Paragraph:
      return renderInlineChildren(paragraph)
    case let code as CodeBlock:
      return renderCodeBlock(code)
    case let list as UnorderedList:
      return renderList(list, start: nil)
    case let list as OrderedList:
      return renderList(list, start: Int(list.startIndex))
    case let quote as BlockQuote:
      let content = NSMutableAttributedString(attributedString: renderBlockChildren(quote))
      var depth = 1
      var parent = quote.parent
      while let ancestor = parent {
        if ancestor is BlockQuote { depth += 1 }
        parent = ancestor.parent
      }
      let marker = TranscriptQuote(depth: depth)
      content.enumerateAttributes(in: content.fullRange) { attributes, range, _ in
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle ?? .default).mutableCopy() as! NSMutableParagraphStyle
        style.firstLineHeadIndent += 19
        style.headIndent += 19
        var markers = attributes[.transcriptQuotes] as? [TranscriptQuote] ?? []
        markers.append(marker)
        content.addAttributes([.paragraphStyle: style, .transcriptQuotes: markers], range: range)
      }
      return content
    case is ThematicBreak:
      return NSAttributedString(string: "\u{fffc}", attributes: [.transcriptRule: true])
    case let table as Table:
      return renderTable(table)
    default:
      if markup.childCount > 0 { return renderBlockChildren(markup) }
      return NSAttributedString(string: plainText(markup), attributes: baseAttributes)
    }
  }

  private func renderList(_ markup: Markup, start: Int?) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    let items = markup.children.compactMap { $0 as? ListItem }
    var depth = 0
    var parent = markup.parent
    while let ancestor = parent {
      if ancestor is OrderedList || ancestor is UnorderedList { depth += 1 }
      parent = ancestor.parent
    }
    for (offset, item) in items.enumerated() {
      if offset > 0 { result.append(NSAttributedString(string: "\n", attributes: baseAttributes)) }
      let checked = item.checkbox.map { $0 == .checked }
      let number = start.map { $0 + offset }
      let markerWidth: CGFloat = checked != nil ? 14 : (number != nil
        ? ("99." as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)]).width : 3)
      let indent = markerWidth + 8 + CGFloat(depth) * 24
      let line = NSMutableAttributedString(attributedString: renderBlockChildren(item))
      line.enumerateAttributes(in: line.fullRange) { attributes, range, _ in
        // A nested list owns its own indentation. Embedded blocks retain their
        // attachment layout and are indented with their containing item.
        guard attributes[.transcriptListMarker] == nil else { return }
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle ?? .default).mutableCopy() as! NSMutableParagraphStyle
        if style.headIndent > indent { return }
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.paragraphSpacing = 0
        line.addAttribute(.paragraphStyle, value: style, range: range)
        if checked == true { line.addAttribute(.foregroundColor, value: TranscriptColors.muted, range: range) }
      }
      if line.length > 0 {
        line.addAttribute(.transcriptListMarker,
          value: TranscriptListMarker(number: number, checked: checked),
          range: NSRange(location: 0, length: 1))
      }
      result.append(line)
    }
    return result
  }

  private func renderCodeBlock(_ code: CodeBlock) -> NSAttributedString {
    var source = code.code
    while source.last == "\n" { source.removeLast() }
    return NSAttributedString(string: "\u{fffc}", attributes: [
      .transcriptCode: CodePaneContent(source: source, language: code.language ?? ""),
    ])
  }

  private func renderTable(_ table: Table) -> NSAttributedString {
    let rows: [Markup] = [table.head] + Array(table.body.children)
    let renderedRows = rows.enumerated().map { rowIndex, row in
      row.children.enumerated().map { column, cell -> NSAttributedString in
        let content = renderInlineChildren(cell)
        content.enumerateAttribute(.font, in: content.fullRange) { value, range, _ in
          if let font = value as? NSFont, font.pointSize == 15 {
            content.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: 14), range: range)
          }
        }
        if rowIndex == 0 { addFontTrait(.boldFontMask, to: content) }
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 22; style.maximumLineHeight = 22
        switch table.columnAlignments[column] {
        case .center?: style.alignment = .center
        case .right?: style.alignment = .right
        default: style.alignment = .left
        }
        content.addAttribute(.paragraphStyle, value: style, range: content.fullRange)
        return content
      }
    }
    return NSAttributedString(string: "\u{fffc}", attributes: [.transcriptTable: TablePaneContent(rows: renderedRows)])
  }

  private func renderBlockChildren(_ markup: Markup, separator: String = "\n")
    -> NSAttributedString
  {
    let result = NSMutableAttributedString(string: "")
    let children = Array(markup.children)
    for (index, child) in children.enumerated() {
      if index > 0 { result.append(NSAttributedString(string: separator, attributes: baseAttributes)) }
      let block = NSMutableAttributedString(attributedString: renderBlock(child))
      if block.length > 0 {
        // RN's normalized styles use 16-point block spacing, not a blank
        // 22-point text line. The final block has allowTrailingMargin=false.
        let lastLine = (block.string as NSString).lineRange(for: NSRange(location: block.length - 1, length: 0))
        block.enumerateAttribute(.paragraphStyle, in: lastLine) { value, range, _ in
          let style = (value as? NSParagraphStyle ?? baseAttributes[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
          let headingMargins: [CGFloat] = [8, 6, 4, 4, 4, 4]
          let margin = (child as? Heading).map { headingMargins[min(5, max(0, $0.level - 1))] } ?? 16
          style.paragraphSpacing = index == children.count - 1 ? 0 : margin
          if child is ThematicBreak { style.paragraphSpacingBefore = 24; style.paragraphSpacing = 24 }
          block.addAttribute(.paragraphStyle, value: style, range: range)
        }
      }
      result.append(block)
    }
    return result
  }

  private func renderInlineChildren(_ markup: Markup) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(string: "")
    for child in markup.children {
      if child is InlineCode, result.length > 0 {
        result.addAttribute(.kern, value: 3.0, range: NSRange(location: result.length - 1, length: 1))
      }
      result.append(renderInline(child))
    }
    return result
  }

  private func renderInline(_ markup: Markup) -> NSAttributedString {
    switch markup {
    case let text as Markdown.Text:
      return NSAttributedString(string: text.string, attributes: baseAttributes)
    case let code as InlineCode:
      return NSAttributedString(
        string: code.code,
        attributes: [
          .font: NSFont(name: "Menlo", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
          .foregroundColor: TranscriptColors.inlineCodeForeground,
          .transcriptInlineCode: true,
          .paragraphStyle: baseAttributes[.paragraphStyle]!,
        ])
    case is SoftBreak:
      return NSAttributedString(string: " ", attributes: baseAttributes)
    case is LineBreak:
      return NSAttributedString(string: "\n", attributes: baseAttributes)
    case let strong as Strong:
      let result = renderInlineChildren(strong)
      addFontTrait(.boldFontMask, to: result)
      return result
    case let emphasis as Emphasis:
      let result = renderInlineChildren(emphasis)
      addFontTrait(.italicFontMask, to: result)
      return result
    case let strike as Strikethrough:
      let result = renderInlineChildren(strike)
      result.addAttribute(
        .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: result.fullRange)
      return result
    case let link as Link:
      let result = renderInlineChildren(link)
      if let destination = link.destination, let url = URL(string: destination) {
        result.addAttributes(
          [
            .link: url, .foregroundColor: TranscriptColors.primary,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
          ],
          range: result.fullRange)
      }
      return result
    case let image as Markdown.Image:
      return renderImage(image)
    default:
      if markup.childCount > 0 { return renderInlineChildren(markup) }
      return NSAttributedString(string: plainText(markup), attributes: baseAttributes)
    }
  }

  private func renderImage(_ markup: Markdown.Image) -> NSAttributedString {
    if imagePolicy == .altText {
      return NSAttributedString(
        string: markup.plainText.isEmpty ? "Image attachment" : markup.plainText,
        attributes: [
          .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
    guard imagePolicy == .loadLocal else {
      return NSAttributedString(string: "Image or attachment omitted", attributes: baseAttributes)
    }
    guard let destination = markup.source, let image = localImage(destination) else {
      return NSAttributedString(
        string: "Image or attachment unavailable", attributes: baseAttributes)
    }
    let sourceSize = image.size
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return NSAttributedString(
        string: "Image or attachment unavailable", attributes: baseAttributes)
    }
    let scale = min(1, 560 / sourceSize.width, 440 / sourceSize.height)
    let attachment = NSTextAttachment()
    attachment.image = image
    attachment.bounds = NSRect(
      origin: .zero,
      size: NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale))
    return NSAttributedString(attachment: attachment)
  }

  private func localImage(_ source: String) -> NSImage? {
    if source.hasPrefix("file://"), let url = URL(string: source) {
      return NSImage(contentsOf: url)
    }
    return source.contains("://") ? nil : NSImage(contentsOfFile: source)
  }

  private func addFontTrait(_ trait: NSFontTraitMask, to text: NSMutableAttributedString) {
    text.enumerateAttribute(.font, in: text.fullRange) { value, range, _ in
      let font = value as? NSFont ?? baseFont
      text.addAttribute(
        .font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: range)
    }
  }

  private func plainText(_ markup: Markup) -> String {
    if let text = markup as? Markdown.Text { return text.string }
    if let code = markup as? InlineCode { return code.code }
    if markup is SoftBreak { return " " }
    if markup is LineBreak { return "\n" }
    return markup.children.map(plainText).joined()
  }


}

extension NSAttributedString {
  fileprivate var fullRange: NSRange { NSRange(location: 0, length: length) }
}
