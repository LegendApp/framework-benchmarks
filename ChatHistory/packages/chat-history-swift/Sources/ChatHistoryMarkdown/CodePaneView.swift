import AppKit

extension NSAttributedString.Key {
  static let transcriptCode = NSAttributedString.Key("ChatHistoryCodePane")
  static let transcriptRule = NSAttributedString.Key("ChatHistoryThematicRule")
}

final class CodePaneContent: NSObject {
  let source: String
  let language: String
  init(source: String, language: String) {
    self.source = source
    self.language = language.split(separator: " ").first.map(String.init) ?? ""
  }
}

/// The same native controls and geometry as RN's ENRMCodeBlockContainerView:
/// an independently scrolling code document, fixed language header and copy button.
@MainActor
final class CodePaneView: NSView {
  private let content: CodePaneContent
  private let scroll = NSScrollView()
  private let code: CodeDrawingView
  private let copyButton = NSButton()
  private let headerFont = NSFont.systemFont(ofSize: 12 * 0.85, weight: .medium)
  private var headerHeight: CGFloat { 13 + ceil(headerFont.ascender - headerFont.descender) }
  var contentHeight: CGFloat { code.codeSize.height + 26 + headerHeight }
  override var isFlipped: Bool { true }

  init(content: CodePaneContent) {
    self.content = content
    code = CodeDrawingView(source: content.source, language: content.language)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 7
    layer?.masksToBounds = true
    scroll.drawsBackground = false
    scroll.hasHorizontalScroller = true
    scroll.hasVerticalScroller = false
    scroll.scrollerStyle = .overlay
    scroll.scrollerKnobStyle = .light
    scroll.documentView = code
    addSubview(scroll)
    copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")?
      .withSymbolConfiguration(.init(pointSize: 12 * 0.72, weight: .regular))
    copyButton.isBordered = false
    copyButton.contentTintColor = TranscriptColors.codeForeground.withAlphaComponent(0.6)
    copyButton.target = self
    copyButton.action = #selector(copyCode)
    copyButton.setAccessibilityLabel("Copy code")
    addSubview(copyButton)
    let menu = NSMenu()
    for (title, action) in [("Copy code", #selector(copyCode)), ("Copy as Markdown", #selector(copyMarkdown))] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    code.menu = menu
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func layout() {
    super.layout()
    let height = headerHeight
    scroll.frame = NSRect(x: 1, y: height, width: max(0, bounds.width - 2), height: max(0, bounds.height - height - 1))
    code.frame = NSRect(x: 0, y: 0, width: max(code.codeSize.width + 24, scroll.bounds.width), height: scroll.bounds.height)
    let iconWidth = min(height, max(0, copyButton.intrinsicContentSize.width))
    copyButton.frame = NSRect(x: max(0, bounds.width - 13 - height + (height - iconWidth) / 2),
      y: max(0, height / 2 - ceil(headerFont.ascender - headerFont.descender) / 2), width: height, height: height)
  }
  override func draw(_ dirtyRect: NSRect) {
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
    TranscriptColors.codeBackground.setFill(); path.fill()
    TranscriptColors.border.setStroke(); path.lineWidth = 1; path.stroke()
    TranscriptColors.codeForeground.withAlphaComponent(0.2).setFill()
    NSRect(x: 1, y: headerHeight + 6.5, width: max(0, bounds.width - 2), height: 1).fill()
    let label = NSAttributedString(string: content.language.capitalized, attributes: [
      .font: headerFont, .foregroundColor: TranscriptColors.codeForeground.withAlphaComponent(0.6),
    ])
    label.draw(at: NSPoint(x: 13, y: headerHeight - label.size().height))
  }
  @objc private func copyCode() { copy(content.source) }
  @objc private func copyMarkdown() {
    // Choose a fence longer than any backtick run in the source.
    let longest = content.source.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
    let fence = String(repeating: "`", count: max(3, longest + 1))
    copy("\(fence)\(content.language)\n\(content.source)\n\(fence)")
  }
  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }
}

@MainActor
private final class CodeDrawingView: NSView {
  private let attributed: NSAttributedString
  let codeSize: NSSize
  override var isFlipped: Bool { true }
  init(source: String, language: String) {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = 18; style.maximumLineHeight = 18
    style.baseWritingDirection = .leftToRight
    let highlighted = NSMutableAttributedString(string: source, attributes: [
      .font: NSFont(name: "Menlo", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular),
      .foregroundColor: TranscriptColors.codeForeground, .paragraphStyle: style,
    ])
    CodeSyntaxHighlighter.apply(to: highlighted, language: language)
    attributed = highlighted
    let size = attributed.boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin).size
    codeSize = NSSize(width: ceil(size.width), height: ceil(size.height))
    super.init(frame: .zero)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityValue(source)
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func draw(_ dirtyRect: NSRect) { attributed.draw(at: NSPoint(x: 12, y: 13)) }
}

@MainActor
final class TranscriptBlockCell: NSTextAttachmentCell {
  var blockSize: NSSize = .zero
  let rule: Bool
  init(rule: Bool = false) { self.rule = rule; super.init(textCell: "") }
  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func cellSize() -> NSSize { MainActor.assumeIsolated { blockSize } }
  override func cellBaselineOffset() -> NSPoint { .zero }
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
    if rule {
      NSColor(srgbRed: 229/255, green: 231/255, blue: 235/255, alpha: 1).setFill()
      NSRect(x: cellFrame.minX, y: cellFrame.minY, width: cellFrame.width, height: 1).fill()
    }
  }
}
