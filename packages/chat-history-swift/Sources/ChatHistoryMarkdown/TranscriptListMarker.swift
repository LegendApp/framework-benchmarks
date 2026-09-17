import AppKit

extension NSAttributedString.Key {
  static let transcriptListMarker = NSAttributedString.Key("ChatHistoryListMarker")
}

final class TranscriptListMarker: NSObject {
  let number: Int?
  let checked: Bool?
  init(number: Int?, checked: Bool?) {
    self.number = number; self.checked = checked
  }

  @MainActor
  func draw(baseline: NSPoint, font: NSFont) {
    let x = baseline.x - 8
    let centerY = baseline.y - font.capHeight / 2
    if let checked {
      let rect = NSRect(x: x - 7, y: centerY - 7, width: 14, height: 14)
      let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
      if checked {
        TranscriptColors.primary.setFill(); path.fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 7))
        check.line(to: NSPoint(x: rect.minX + 6, y: rect.minY + 10))
        check.line(to: NSPoint(x: rect.minX + 11, y: rect.minY + 4))
        NSColor.white.setStroke(); check.lineWidth = 1.5; check.stroke()
      } else {
        TranscriptColors.muted.setStroke(); path.lineWidth = 1.5; path.stroke()
      }
    } else if let number {
      let label = NSAttributedString(string: "\(number).", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: TranscriptColors.muted,
      ])
      label.draw(at: NSPoint(x: x - label.size().width, y: baseline.y - font.ascender))
    } else {
      TranscriptColors.muted.setFill()
      NSBezierPath(ovalIn: NSRect(x: x - 3, y: centerY - 3, width: 6, height: 6)).fill()
    }
  }
}
