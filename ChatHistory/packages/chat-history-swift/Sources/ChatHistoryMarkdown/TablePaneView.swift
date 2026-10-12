import AppKit

extension NSAttributedString.Key {
  static let transcriptTable = NSAttributedString.Key("ChatHistoryTablePane")
}

/// RN TableContainerView's content-driven 60...316 pt columns, 8/6 pt cell
/// padding and 1 pt border. Width belongs to the table; narrow views scroll it.
@MainActor
final class TablePaneContent: NSObject {
  let rows: [[NSAttributedString]]
  let columnWidths: [CGFloat]
  let rowHeights: [CGFloat]
  let size: NSSize
  init(rows: [[NSAttributedString]]) {
    self.rows = rows
    var widths = [CGFloat](repeating: 60, count: rows.map(\.count).max() ?? 0)
    let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    for row in rows {
      for (column, cell) in row.enumerated() {
        let rect = cell.boundingRect(with: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude), options: options)
        widths[column] = max(widths[column], min(316, ceil(rect.width) + 16))
      }
    }
    columnWidths = widths
    rowHeights = rows.map { row in
      row.enumerated().map { column, cell in
        ceil(cell.boundingRect(with: NSSize(width: widths[column] - 16, height: CGFloat.greatestFiniteMagnitude), options: options).height) + 12
      }.max() ?? 0
    }
    size = NSSize(width: widths.reduce(0, +) + 1, height: rowHeights.reduce(0, +) + 1)
  }
}

@MainActor
final class TablePaneView: NSScrollView {
  let content: TablePaneContent
  init(content: TablePaneContent) {
    self.content = content
    super.init(frame: .zero)
    drawsBackground = false
    hasVerticalScroller = false
    hasHorizontalScroller = true
    scrollerStyle = .overlay
    let grid = TableGridView(content: content)
    grid.frame.size = content.size
    documentView = grid
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.masksToBounds = true
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
private final class TableGridView: NSView {
  private let content: TablePaneContent
  override var isFlipped: Bool { true }
  init(content: TablePaneContent) {
    self.content = content
    super.init(frame: .zero)
    let menu = NSMenu()
    let item = NSMenuItem(title: "Copy table", action: #selector(copyTable), keyEquivalent: "")
    item.target = self; menu.addItem(item); self.menu = menu
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityValue(content.rows.map { $0.map(\.string).joined(separator: ", ") }.joined(separator: "\n"))
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func draw(_ dirtyRect: NSRect) {
    let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
    NSGraphicsContext.saveGraphicsState()
    outline.addClip()
    var y: CGFloat = 0
    for (rowIndex, row) in content.rows.enumerated() {
      let height = content.rowHeights[rowIndex]
      let background = rowIndex == 0 ? TranscriptColors.tableHeader
        : (rowIndex % 2 == 1 ? TranscriptColors.surface : TranscriptColors.tableRowAlt)
      background.setFill()
      NSRect(x: 0, y: y, width: bounds.width, height: height).fill()
      var x: CGFloat = 0
      for (column, cell) in row.enumerated() {
        let width = content.columnWidths[column]
        cell.draw(with: NSRect(x: x + 8, y: y + 6, width: width - 16, height: height - 12),
          options: [.usesLineFragmentOrigin, .usesFontLeading])
        if column > 0 {
          TranscriptColors.border.setFill()
          NSRect(x: x, y: y, width: 1, height: height).fill()
        }
        x += width
      }
      if rowIndex > 0 {
        TranscriptColors.border.setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
      }
      y += height
    }
    NSGraphicsContext.restoreGraphicsState()
    TranscriptColors.border.setStroke(); outline.lineWidth = 1; outline.stroke()
  }
  @objc private func copyTable() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(content.rows.map { $0.map(\.string).joined(separator: "\t") }.joined(separator: "\n"), forType: .string)
  }
}
