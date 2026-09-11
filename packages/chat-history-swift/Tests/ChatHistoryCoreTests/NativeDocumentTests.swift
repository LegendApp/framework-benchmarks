import Foundation
import Testing

@testable import ChatHistoryCore

private let nativeFixtureRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent()
  .appending(path: "chat-history/tests/fixtures")

@Test func nativeDocumentMatchesSwiftReference() throws {
  for name in ["codex.jsonl", "claude.jsonl", "codex-response-user.jsonl"] {
    let provider: ChatProvider = name.hasPrefix("claude") ? .claude : .codex
    let path = nativeFixtureRoot.appending(path: name).path
    let native = try openChatFile(provider: provider, path: path, parser: .cpp)
    let swift = try openChatFile(provider: provider, path: path, parser: .swift)
    #expect(swift.rows.cachedRowCount == 0)
    #expect(swift.contentDigest == native.contentDigest)
    #expect(swift.rows.cachedRowCount == 0)
    #expect(swift.warningCount == native.warningCount)
    #expect(normalizedContentDigest(swift.rows) == native.contentDigest)
    print("Swift lazy: \(swift.timing)")
    let reference = try openChatFileSwiftReference(provider: provider, path: path)
    #expect(native.recordCount == reference.recordCount)
    #expect(native.warningCount == reference.warningCount)
    #expect(native.rows.map(\.id) == reference.rows.map(\.id))
    #expect(native.rows.allSatisfy { $0.nativeText?.decodedFieldCount == 0 })
    #expect(native.contentDigest == normalizedContentDigest(reference.rows))
    // Digest validation must not fill every UI text cache during memory runs.
    #expect(native.rows.allSatisfy { $0.nativeText?.decodedFieldCount == 0 })
    #expect(normalizedContentDigest(native.rows) == native.contentDigest)
    let encoded = try JSONEncoder().encode(native)
    let roundTrip = try JSONDecoder().decode(ChatDocument.self, from: encoded)
    #expect(roundTrip.contentDigest == native.contentDigest)
  }
}

@Test func rowRetainsMappingAndDecodesOnlyRequestedText() throws {
  var document: ChatDocument? = try openChatFile(
    provider: .codex, path: nativeFixtureRoot.appending(path: "codex.jsonl").path)
  let row = document!.rows[0]
  let otherRow = document!.rows[2]
  document = nil
  #expect(row.nativeText?.decodedFieldCount == 0)
  #expect(row.markdown == "Hello ☺\nworld\n")
  #expect(row.nativeText?.decodedFieldCount == 1)
  #expect(row.markdown == "Hello ☺\nworld\n")
  #expect(row.nativeText?.decodedFieldCount == 1)
  #expect(otherRow.nativeText?.decodedFieldCount == 0)
}

@Test func nativeOpenReportsMissingFile() {
  #expect(throws: (any Error).self) {
    try openChatFile(provider: .codex, path: "/nonexistent/chat-history-fixture.jsonl")
  }
}

@Test func pinnedCorpusMatchesCanonicalRowsWhenConfigured() throws {
  guard let manifestPath = ProcessInfo.processInfo.environment["CHAT_HISTORY_TEST_FIXTURES"] else {
    return
  }
  let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
  let manifest = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  for fixture in manifest["fixtures"] as! [[String: Any]] {
    let provider = ChatProvider(rawValue: fixture["provider"] as! String)!
    let path = fixture["path"] as! String
    let native = try openChatFile(provider: provider, path: path, parser: .cpp)
    #expect(native.rows.allSatisfy { $0.nativeText?.decodedFieldCount == 0 })
    let swift = try openChatFile(provider: provider, path: path, parser: .swift)
    #expect(swift.rows.cachedRowCount == 0)
    #expect(swift.contentDigest == native.contentDigest)
    #expect(swift.rows.cachedRowCount == 0)
    #expect(swift.warningCount == native.warningCount)
    #expect(normalizedContentDigest(swift.rows) == native.contentDigest)
    print("Swift lazy: \(swift.timing)")
    let reference = try openChatFileSwiftReference(provider: provider, path: path)
    #expect(native.rows.count == reference.rows.count)
    #expect(native.warningCount == reference.warningCount)
    #expect(native.contentDigest == normalizedContentDigest(reference.rows))
    #expect(normalizedContentDigest(native.rows) == native.contentDigest)
    print(
      "Native core: \(native.sourceBytes) bytes, \(native.rows.count) rows, \(native.timing.nativeTotalMs) ms; Swift reference \(reference.timing.nativeTotalMs) ms; digest \(native.contentDigest)"
    )
  }
}
