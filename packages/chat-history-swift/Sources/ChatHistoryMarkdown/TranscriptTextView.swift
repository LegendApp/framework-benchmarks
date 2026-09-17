import AppKit

/// Selectable, non-scrolling message text. Measurement and drawing share one
/// TextKit layout manager; a width change invalidates only the measured size.
@MainActor
public final class TranscriptTextView: NSTextView {
  private struct Block {
    let index: Int
    let cell: TranscriptBlockCell
    let view: NSView?
    let indent: CGFloat
  }
  private var blocks: [Block] = []
  private var measuredSize: NSSize?
  private var content: NSAttributedString?
  public var expandsToWidth = true {
    didSet {
      guard oldValue != expandsToWidth else { return }
      measuredSize = nil
      invalidateIntrinsicContentSize()
    }
  }
  public var measurementWidth: CGFloat = 1 {
    didSet {
      guard oldValue != measurementWidth else { return }
      textContainer?.containerSize = NSSize(width: max(1, measurementWidth), height: CGFloat.greatestFiniteMagnitude)
      for block in blocks {
        let available = max(1, measurementWidth - block.indent)
        block.cell.blockSize.width = min(available, (block.view as? TablePaneView)?.content.size.width ?? available)
      }
      if !blocks.isEmpty, let textStorage {
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage.length), actualCharacterRange: nil)
      }
      measuredSize = nil
      invalidateIntrinsicContentSize()
      needsLayout = true
    }
  }

  public init() {
    let storage = NSTextStorage()
    let manager = NSLayoutManager()
    manager.usesFontLeading = false
    let container = NSTextContainer(containerSize: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    container.widthTracksTextView = false
    container.heightTracksTextView = false
    storage.addLayoutManager(manager)
    manager.addTextContainer(container)
    super.init(frame: .zero, textContainer: container)
    isEditable = false
    isSelectable = true
    isRichText = true
    drawsBackground = false
    textContainerInset = .zero
    isVerticallyResizable = false
    isHorizontallyResizable = false
    setContentCompressionResistancePriority(.required, for: .vertical)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  public func setContent(_ value: NSAttributedString) {
    guard content !== value else { return }
    content = value
    setSelectedRange(NSRange(location: 0, length: 0))
    for block in blocks { block.view?.removeFromSuperview() }
    blocks.removeAll(keepingCapacity: true)
    let display = NSMutableAttributedString(attributedString: value)
    value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
      let code = attributes[.transcriptCode] as? CodePaneContent
      let table = attributes[.transcriptTable] as? TablePaneContent
      let rule = attributes[.transcriptRule] as? Bool ?? false
      guard code != nil || table != nil || rule else { return }
      let pane: NSView? = code.map { CodePaneView(content: $0) } ?? table.map { TablePaneView(content: $0) }
      let cell = TranscriptBlockCell(rule: rule)
      let style = (attributes[.paragraphStyle] as? NSParagraphStyle ?? .default).mutableCopy() as! NSMutableParagraphStyle
      style.minimumLineHeight = 0; style.maximumLineHeight = 0
      cell.blockSize = NSSize(width: min(max(1, measurementWidth - style.headIndent), table?.size.width ?? measurementWidth),
        height: (pane as? CodePaneView)?.contentHeight ?? table?.size.height ?? 1)
      let attachment = NSTextAttachment()
      attachment.attachmentCell = cell
      display.addAttributes([.attachment: attachment, .font: NSFont.systemFont(ofSize: 0.1), .paragraphStyle: style], range: range)
      blocks.append(Block(index: range.location, cell: cell, view: pane, indent: style.headIndent))
      if let pane { addSubview(pane) }
    }
    textStorage?.setAttributedString(display)
    needsLayout = true
    measuredSize = nil
    invalidateIntrinsicContentSize()
    needsDisplay = true
  }

  public func size(fittingWidth width: CGFloat) -> NSSize {
    measurementWidth = max(1, width)
    if let measuredSize { return measuredSize }
    guard let layoutManager, let textContainer else { return .zero }
    layoutManager.ensureLayout(for: textContainer)
    let used = layoutManager.usedRect(for: textContainer)
    // NSTextView can report a container-wide usedRect after attachment to a
    // view hierarchy. Glyph bounds preserve compact user-message bubbles.
    let textWidth = expandsToWidth ? measurementWidth : ceil(layoutManager.boundingRect(
      forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs), in: textContainer).maxX)
    let size = NSSize(width: min(measurementWidth, textWidth), height: ceil(used.height))
    measuredSize = size
    return size
  }

  public override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    guard let textStorage, let layoutManager, let textContainer else { return }
    var quotes: [ObjectIdentifier: (TranscriptQuote, NSRect)] = [:]
    textStorage.enumerateAttribute(.transcriptQuotes, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
      guard let markers = value as? [TranscriptQuote] else { return }
      let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
      for marker in markers {
        let id = ObjectIdentifier(marker)
        quotes[id] = (marker, quotes[id]?.1.union(bounds) ?? bounds)
      }
    }
    for (marker, bounds) in quotes.values.sorted(by: { $0.0.depth < $1.0.depth }) {
      let x = CGFloat(marker.depth - 1) * 19
      let background = NSRect(x: x, y: bounds.minY, width: max(0, measurementWidth - x), height: bounds.height)
      guard background.intersects(rect) else { continue }
      TranscriptColors.blockquoteBackground.setFill(); background.fill()
      TranscriptColors.blockquoteBorder.setFill()
      NSRect(x: x, y: background.minY, width: 3, height: background.height).fill()
    }
    textStorage.enumerateAttribute(.transcriptInlineCode, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
      guard value != nil else { return }
      let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, line, _ in
        let intersection = NSIntersectionRange(glyphs, line)
        guard intersection.length > 0 else { return }
        var background = layoutManager.boundingRect(forGlyphRange: intersection, in: textContainer)
        background.origin.y += 4
        if intersection.location == glyphs.location { background.origin.x -= 3; background.size.width += 3 }
        if NSMaxRange(intersection) == NSMaxRange(glyphs) { background.size.width += 3 }
        guard background.intersects(rect) else { return }
        TranscriptColors.inlineCodeBackground.setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
      }
    }
  }

  public override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let textStorage, let layoutManager else { return }
    textStorage.enumerateAttribute(.transcriptListMarker, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
      guard let marker = value as? TranscriptListMarker else { return }
      let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
      let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
      guard line.intersects(dirtyRect) else { return }
      let position = layoutManager.location(forGlyphAt: glyph)
      let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
      marker.draw(baseline: NSPoint(x: line.minX + position.x, y: line.minY + position.y), font: font)
    }
  }

  func plainText(in range: NSRange) -> String {
    guard let content, range.length > 0 else { return "" }
    let output = NSMutableString()
    content.enumerateAttributes(in: range) { attributes, range, _ in
      if let code = attributes[.transcriptCode] as? CodePaneContent {
        output.append(code.source)
      } else if let table = attributes[.transcriptTable] as? TablePaneContent {
        output.append(table.rows.map { $0.map(\.string).joined(separator: "\t") }.joined(separator: "\n"))
      } else if attributes[.transcriptRule] != nil {
        output.append("---")
      } else {
        output.append((content.string as NSString).substring(with: range))
      }
    }
    return output as String
  }

  public override func copy(_ sender: Any?) {
    guard selectedRange().length > 0 else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(plainText(in: selectedRange()), forType: .string)
  }

  public override func layout() {
    super.layout()
    guard let layoutManager, let textContainer else { return }
    layoutManager.ensureLayout(for: textContainer)
    for block in blocks {
      let range = layoutManager.glyphRange(forCharacterRange: NSRange(location: block.index, length: 1), actualCharacterRange: nil)
      let rect = layoutManager.boundingRect(forGlyphRange: range, in: textContainer)
      block.view?.frame = NSRect(x: rect.minX, y: rect.minY, width: block.cell.blockSize.width, height: block.cell.blockSize.height)
    }
  }

  public override var intrinsicContentSize: NSSize { size(fittingWidth: measurementWidth) }
}
