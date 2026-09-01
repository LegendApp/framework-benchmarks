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
  private let baseFont = NSFont.systemFont(ofSize: 14)
  private let baseAttributes: [NSAttributedString.Key: Any]
  private let imagePolicy: RichMarkdownImagePolicy

  init(imagePolicy: RichMarkdownImagePolicy) {
    self.imagePolicy = imagePolicy
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3
    baseAttributes = [
      .font: baseFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraph,
    ]
  }

  func render(_ document: Document) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    for (index, child) in document.children.enumerated() {
      if index > 0 { result.append(NSAttributedString(string: "\n\n")) }
      result.append(renderBlock(child))
    }
    return result
  }

  private func renderBlock(_ markup: Markup) -> NSAttributedString {
    switch markup {
    case let heading as Heading:
      let result = renderInlineChildren(heading)
      let sizes: [CGFloat] = [26, 22, 19, 17, 15, 14]
      let size = sizes[min(max(heading.level - 1, 0), sizes.count - 1)]
      result.addAttributes(
        [.font: NSFont.systemFont(ofSize: size, weight: .bold)],
        range: result.fullRange)
      return result
    case let paragraph as Paragraph:
      return renderInlineChildren(paragraph)
    case let code as CodeBlock:
      let text = NSMutableAttributedString(
        string: code.code,
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
          .foregroundColor: NSColor.labelColor,
          .backgroundColor: NSColor.controlBackgroundColor,
        ])
      let style = NSMutableParagraphStyle()
      style.lineSpacing = 2
      text.addAttribute(.paragraphStyle, value: style, range: text.fullRange)
      return text
    case let list as UnorderedList:
      return renderList(list, start: nil)
    case let list as OrderedList:
      return renderList(list, start: Int(list.startIndex))
    case let quote as BlockQuote:
      let content = renderBlockChildren(quote)
      return prefixLines(in: content, with: "│ ", color: .secondaryLabelColor)
    case is ThematicBreak:
      return NSAttributedString(
        string: "────────────────────────",
        attributes: [.foregroundColor: NSColor.separatorColor])
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
    for (offset, item) in items.enumerated() {
      if offset > 0 { result.append(NSAttributedString(string: "\n")) }
      let marker = start.map { "\($0 + offset). " } ?? "• "
      let body = renderBlockChildren(item, separator: "\n")
      let line = NSMutableAttributedString(string: marker, attributes: baseAttributes)
      line.append(body)
      let style = NSMutableParagraphStyle()
      style.lineSpacing = 3
      style.firstLineHeadIndent = 0
      style.headIndent = 22
      style.paragraphSpacing = 4
      line.addAttribute(.paragraphStyle, value: style, range: line.fullRange)
      result.append(line)
    }
    return result
  }

  private func renderTable(_ table: Table) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    let rows: [Markup] = [table.head] + Array(table.body.children)
    for (index, row) in rows.enumerated() {
      if index > 0 { result.append(NSAttributedString(string: "\n")) }
      let cells = row.children.map { plainText($0) }
      let line = NSMutableAttributedString(
        string: cells.joined(separator: "   │   "), attributes: baseAttributes)
      if index == 0 {
        line.addAttributes(
          [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)], range: line.fullRange)
      }
      result.append(line)
    }
    return result
  }

  private func renderBlockChildren(_ markup: Markup, separator: String = "\n\n")
    -> NSAttributedString
  {
    let result = NSMutableAttributedString(string: "")
    for (index, child) in markup.children.enumerated() {
      if index > 0 { result.append(NSAttributedString(string: separator)) }
      result.append(renderBlock(child))
    }
    return result
  }

  private func renderInlineChildren(_ markup: Markup) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(string: "")
    for child in markup.children { result.append(renderInline(child)) }
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
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
          .foregroundColor: NSColor.labelColor,
          .backgroundColor: NSColor.controlBackgroundColor,
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
            .link: url, .foregroundColor: NSColor.linkColor,
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
      return NSAttributedString(string: "Image or attachment unavailable", attributes: baseAttributes)
    }
    let sourceSize = image.size
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return NSAttributedString(string: "Image or attachment unavailable", attributes: baseAttributes)
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

  private func prefixLines(
    in value: NSAttributedString, with prefix: String, color: NSColor
  ) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    let lines = value.string.split(separator: "\n", omittingEmptySubsequences: false)
    var location = 0
    for (index, line) in lines.enumerated() {
      if index > 0 { result.append(NSAttributedString(string: "\n")) }
      result.append(NSAttributedString(string: prefix, attributes: [.foregroundColor: color]))
      let length = (line as NSString).length
      if length > 0 {
        result.append(value.attributedSubstring(from: NSRange(location: location, length: length)))
      }
      location += length + 1
    }
    return result
  }
}

extension NSAttributedString {
  fileprivate var fullRange: NSRange { NSRange(location: 0, length: length) }
}
