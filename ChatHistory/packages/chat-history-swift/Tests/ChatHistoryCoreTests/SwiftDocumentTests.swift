import Foundation
import Testing

@testable import ChatHistoryCore

@Test func swiftSelectiveEnvelopeAndLazyMetadataMatchCPP() throws {
  let lines = [
    #"{"timestamp":"2026-01-01T00:00:00Z","ordinal":1,"type":"event_msg","payload":{"type":"user_message","message":"héllo \\ \ud83d\ude80","images":[],"local_images":[]}}"#,
    #"{"payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"reordered envelope"}]},"type":"response_item","timestamp":"2026-01-01T00:00:01Z"}"#,
    #"{"timestamp":"2026-01-01T00:00:02Z","type":"response_item","payload":{"type":"function_call","call_id":"a","name":"Read","arguments":"{}"}}"#,
    #"{"timestamp":"2026-01-01T00:00:03Z","type":"response_item","payload":{"type":"function_call_output","call_id":"a","output":{"ignored":"large non-string result"}}}"#,
    #"{"timestamp":"2026-01-01T00:00:04Z","type":"response_item","payload":{"type":"message","role":"assistant","content":"done"}}"#,
    "not json",
  ]
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString + ".jsonl")
  try Data(lines.joined(separator: "\r\n").utf8).write(to: file)
  defer { try? FileManager.default.removeItem(at: file) }
  var swift: ChatDocument? = try openChatFile(provider: .codex, path: file.path, parser: .swift)
  let cpp = try openChatFile(provider: .codex, path: file.path, parser: .cpp)
  #expect(swift!.rows.cachedRowCount == 0)
  #expect(swift!.contentDigest == cpp.contentDigest)
  #expect(swift!.warningCount == cpp.warningCount)
  #expect(swift!.rows.cachedRowCount == 0)
  let row = swift!.rows[0]
  #expect(swift!.rows.cachedRowCount == 1)
  #expect(row.nativeText?.decodedFieldCount == 0)
  swift = nil
  #expect(row.markdown == "héllo \\ 🚀")
  #expect(row.nativeText?.decodedFieldCount == 1)
}

@MainActor
@Test func changingConversationCancelsTheOldDemoStream() async throws {
  let demo = ChatDemo()
  demo.send("old conversation")
  try await Task.sleep(for: .milliseconds(450))
  #expect(demo.rows.count == 2)
  demo.reset()
  demo.send("new conversation")
  try await Task.sleep(for: .milliseconds(450))
  #expect(demo.rows.count == 2)
  #expect(demo.rows.first?.markdown == "new conversation")
  #expect(demo.rows.last?.markdown.hasPrefix("This") == true)
  demo.reset()
  try await Task.sleep(for: .milliseconds(60))
  #expect(demo.rows.isEmpty)
}
