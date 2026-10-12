// Appended to a temporary copy of the production SwiftUI source.
@main
@MainActor
private enum SwiftUILayoutQA {
  static func main() {
    _ = NSApplication.shared
    guard #available(macOS 26, *) else { return }
    func row(_ text: String, kind: ChatRowKind = .assistant) -> ChatRow {
      ChatRow(fileChanges: [], hasImagePlaceholder: false, id: UUID().uuidString,
        imageSources: [], kind: kind, markdown: text, toolName: "", toolPreview: "", toolStatus: .none)
    }
    let cache = TranscriptMarkdownCache()
    for (text, expectedHeight) in [("one  \ntwo  \nthree", 66.0), ("# Heading", 28.0), ("```text\none\ntwo\nthree\n```", 72.0)] {
      let text = RichMarkdownText(rendered: cache.render(row: row(text), loadImages: false), expand: true)
      let controller = NSHostingController(rootView: text)
      let size = controller.sizeThatFits(in: CGSize(width: 300, height: 10000))
      precondition(abs(size.height - expectedHeight) < 0.5, "Line height mismatch: \(size), expected \(expectedHeight)")
      print("Verified text height \(size.height)")
    }
    let user = NSHostingController(rootView: TranscriptRow(loadImages: false, row: row("Short", kind: .user), markdownCache: cache))
    let userSize = user.sizeThatFits(in: CGSize(width: 1020, height: 10000))
    precondition(abs(userSize.height - 62) < 0.5, "User row padding/line height mismatch: \(userSize)")
    let long = NSHostingController(rootView: TranscriptRow(loadImages: false, row: row(String(repeating: "responsive text ", count: 100)), markdownCache: cache))
    let wide = long.sizeThatFits(in: CGSize(width: 1020, height: 10000))
    let narrow = long.sizeThatFits(in: CGSize(width: 400, height: 10000))
    precondition(narrow.height > wide.height && narrow.height.isFinite, "Text did not rewrap at the narrower width")
    print("Verified user height \(userSize.height), responsive heights \(wide.height) / \(narrow.height)")
  }
}
