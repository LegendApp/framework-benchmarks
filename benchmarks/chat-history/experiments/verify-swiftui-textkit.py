#!/usr/bin/env python3
"""Exercise the production SwiftUI TextKit representable at changing widths."""
from pathlib import Path
import subprocess
import tempfile
import json

repo = Path(__file__).resolve().parents[3]
source = (repo / "apps/chat-history-swiftui/Sources/ChatHistorySwiftUI/main.swift").read_text().replace("@main\n", "", 1)
source += r'''
@main @MainActor enum TextKitLayoutQA {
  static func main() {
    _ = NSApplication.shared
    let text = RichMarkdownRenderer.render(String(repeating: "A **formatted** message with a [link](https://example.com) and enough words to require wrapping at a narrower width.\n\n", count: 100))
    let host = NSHostingController(rootView: RichMarkdownText(rendered: text, expand: true))
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    var heights: [CGFloat] = []
    for width: CGFloat in [800, 400, 800] {
      let size = host.sizeThatFits(in: NSSize(width: width, height: 1000000))
      host.view.frame = NSRect(origin: .zero, size: size)
      host.view.layoutSubtreeIfNeeded()
      let view = descendants(host.view).compactMap { $0 as? TranscriptTextView }.first!
      precondition(view.string == text.string)
      precondition(abs(view.measurementWidth - width) < 1)
      precondition(size.height > 0 && view.bounds.height + 1 >= view.intrinsicContentSize.height)
      heights.append(size.height)
      print("SwiftUI width \(width), height \(size.height): content and bounds verified")
    }
    precondition(heights[1] > heights[0] && heights[0] == heights[2])
    let short = NSHostingController(rootView: MessageLayout(user: true) {
      VStack(alignment: .leading) {
        RichMarkdownText(rendered: RichMarkdownRenderer.render("yes"), expand: false)
      }.padding(.horizontal, 16).padding(.vertical, 12)
    })
    let shortSize = short.sizeThatFits(in: NSSize(width: 800, height: 1000))
    short.view.frame = NSRect(origin: .zero, size: shortSize)
    short.view.layoutSubtreeIfNeeded()
    let shortText = descendants(short.view).compactMap { $0 as? TranscriptTextView }.first!
    FileHandle.standardError.write(Data("Short width: \(shortText.bounds.width), measured: \(shortText.size(fittingWidth: 600)), expand: \(shortText.expandsToWidth), container: \(shortText.textContainer!.containerSize)\n".utf8))
    precondition(shortText.bounds.width > 0 && shortText.bounds.width < 100)

  }
}
'''
with tempfile.TemporaryDirectory(prefix="swiftui-textkit-qa-") as directory:
    package = Path(directory)
    target = package / "Sources/LayoutQA"
    target.mkdir(parents=True)
    (target / "main.swift").write_text(source)
    dependency = json.dumps(str(repo / "packages/chat-history-swift"))
    (package / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LayoutQA", platforms: [.macOS(.v14)], dependencies: [.package(path: {dependency})], targets: [.executableTarget(name: "LayoutQA", dependencies: [.product(name: "ChatHistoryCore", package: "chat-history-swift"), .product(name: "ChatHistoryMarkdown", package: "chat-history-swift")])])
''')
    subprocess.run(["swift", "run", "--package-path", directory, "LayoutQA"], check=True)
