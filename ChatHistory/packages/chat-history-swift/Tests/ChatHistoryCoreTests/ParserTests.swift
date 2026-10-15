import Foundation
import Testing

@testable import ChatHistoryCore

private let fixtureRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appending(path: "chat-history/tests/fixtures")

private func fixture(_ name: String) throws -> String {
  try String(contentsOf: fixtureRoot.appending(path: name), encoding: .utf8)
}

@Test func publishedSamplesMatchNativeAndSwiftParsers() throws {
  let root = fixtureRoot.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
  let data = try Data(contentsOf: root.appending(path: "manifest.json"))
  let manifest = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  for sample in manifest["fixtures"] as! [[String: Any]] {
    let name = sample["path"] as! String
    guard name.hasSuffix(".jsonl") else { continue }
    let provider = ChatProvider(rawValue: sample["provider"] as! String)!
    let path = root.appending(path: name).path
    let native = try openChatFile(provider: provider, path: path, parser: .cpp)
    let swift = try openChatFile(provider: provider, path: path, parser: .swift)
    #expect(!native.rows.isEmpty)
    #expect(native.sourceBytes == sample["sourceBytes"] as! Int)
    #expect(native.contentDigest == swift.contentDigest)
    #expect(native.warningCount == 0)
    #expect(native.warningCount == swift.warningCount)
  }
}

@Test func normalizesCodexHistory() throws {
  let result = parseChatText(provider: .codex, text: try fixture("codex.jsonl"))
  #expect(result.recordCount == 14)
  #expect(result.warningCount == 2)
  #expect(result.rows.map(\.kind) == [.user, .tool, .assistant, .files])
  #expect(result.rows[0].markdown == "Hello ☺\nworld\n")
  #expect(result.rows[1].toolName == "Worked for 4s")
  #expect(result.rows[1].toolPreview == "Read files, created an image")
  #expect(result.rows[2].markdown == "Done **quickly**.\n\n```text\n::git-commit{example}\n```")
  #expect(
    result.rows[3].fileChanges == [
      ChatFileChange(additions: 3, deletions: 2, path: "apps/demo.ts"),
      ChatFileChange(additions: 1, deletions: 0, path: "packages/helper.ts"),
      ChatFileChange(additions: 0, deletions: 2, path: "packages/old.ts"),
    ])
  #expect(normalizedContentDigest(result.rows) == "ea203684aeae72fb")
}

@Test func normalizesLatestClaudeMainChain() throws {
  let result = parseChatText(provider: .claude, text: try fixture("claude.jsonl"))
  #expect(result.recordCount == 8)
  #expect(result.warningCount == 1)
  #expect(result.rows.map(\.kind) == [.user, .tool, .assistant])
  #expect(result.rows[0].markdown == "Start here")
  #expect(result.rows[1].toolName == "Worked for 3s")
  #expect(result.rows[1].toolPreview == "I will check.\n\nRead files")
  #expect(result.rows[2].markdown == "Latest answer")
  #expect(result.rows[2].hasImagePlaceholder)
  #expect(normalizedContentDigest(result.rows) == "4cb20d4c68d78408")
}

@Test func supportsCurrentCodexResponseUserMessages() throws {
  let result = parseChatText(provider: .codex, text: try fixture("codex-response-user.jsonl"))
  #expect(result.rows.map(\.kind) == [.user, .assistant])
  #expect(result.rows.map(\.markdown) == ["Current-format request", "Current-format answer"])
}
