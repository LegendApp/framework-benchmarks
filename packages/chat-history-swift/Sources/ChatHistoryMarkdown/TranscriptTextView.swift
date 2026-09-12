import AppKit

/// Selectable, non-scrolling message text. Measurement and drawing share one
/// TextKit layout manager; a width change invalidates only the measured size.
@MainActor
public final class TranscriptTextView: NSTextView {
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
      measuredSize = nil
      invalidateIntrinsicContentSize()
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
    textStorage?.setAttributedString(value)
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

  public override var intrinsicContentSize: NSSize { size(fittingWidth: measurementWidth) }
}
