import AppKit

extension NSAttributedString.Key {
  static let transcriptInlineCode = NSAttributedString.Key("ChatHistoryInlineCode")
  static let transcriptQuotes = NSAttributedString.Key("ChatHistoryQuotes")
}
final class TranscriptQuote: NSObject {
  let depth: Int
  init(depth: Int) { self.depth = depth }
}
