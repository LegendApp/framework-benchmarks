import AppKit
import Highlighter

@MainActor
enum CodeSyntaxHighlighter {
  static let languages: [String: String] = [
    "bash": "bash",
    "c": "c",
    "cc": "cpp",
    "cpp": "cpp",
    "cs": "csharp",
    "csharp": "csharp",
    "css": "css",
    "cxx": "cpp",
    "go": "go",
    "golang": "go",
    "html": "xml",
    "java": "java",
    "javascript": "javascript",
    "js": "javascript",
    "json": "json",
    "jsx": "javascript",
    "markdown": "markdown",
    "md": "markdown",
    "php": "php",
    "py": "python",
    "python": "python",
    "rb": "ruby",
    "rs": "rust",
    "ruby": "ruby",
    "rust": "rust",
    "sh": "bash",
    "shell": "bash",
    "swift": "swift",
    "ts": "typescript",
    "tsx": "typescript",
    "typescript": "typescript",
    "yaml": "yaml",
    "yml": "yaml",
    "zsh": "bash"
  ]
  private static let engine: Highlighter? = {
    let engine = Highlighter()
    engine?.ignoreIllegals = true
    _ = engine?.setTheme("github-dark", withFont: "Menlo", ofSize: 12)
    return engine
  }()

  static func apply(to output: NSMutableAttributedString, language: String) {
    let source = output.string
    guard let language = languages[language.lowercased()], source.utf8.count <= 51_200,
      source.reduce(1, { $1 == "\n" ? $0 + 1 : $0 }) <= 2_000,
      let highlighted = engine?.highlight(source, as: language), highlighted.string == source else { return }
    // Retain the transcript's font, paragraph metrics and base foreground.
    highlighted.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: highlighted.length)) { color, range, _ in
      guard let color = color as? NSColor,
        let rgb = color.usingColorSpace(.sRGB) else { return }
      let hex = (Int((rgb.redComponent * 255).rounded()) << 16) | (Int((rgb.greenComponent * 255).rounded()) << 8) | Int((rgb.blueComponent * 255).rounded())
      if hex != 0xc9d1d9 { output.addAttribute(.foregroundColor, value: color, range: range) }
    }
  }
}
