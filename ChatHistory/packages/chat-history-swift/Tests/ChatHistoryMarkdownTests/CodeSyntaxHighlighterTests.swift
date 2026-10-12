import AppKit
@testable import ChatHistoryMarkdown
import Testing

@Test @MainActor
func allSyntaxLanguagesPreserveSourceAndProduceColors() throws {
  struct Fixture: Decodable { let language: String; let source: String }
  var root = URL(fileURLWithPath: #filePath)
  for _ in 0..<6 { root.deleteLastPathComponent() }
  let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("ChatHistory/benchmark/syntax-highlighting-fixtures.json")))
  for fixture in fixtures {
    let output = NSMutableAttributedString(string: fixture.source)
    CodeSyntaxHighlighter.apply(to: output, language: fixture.language)
    #expect(output.string == fixture.source)
    var colored = false
    output.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: output.length)) { value, _, _ in if value != nil { colored = true } }
    #expect(colored, "No syntax tokens for \(fixture.language)")
  }
}
@Test @MainActor
func syntaxFallbackRetainsWholeSource() {
  for (source, language) in [(String(repeating: "😀", count: 12801), "js"), (String(repeating: "\n", count: 2000), "js"), ("const x = 42;", "unknown")] {
    let output = NSMutableAttributedString(string: source)
    CodeSyntaxHighlighter.apply(to: output, language: language)
    #expect(output.string == source)
    #expect(output.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
  }
}
