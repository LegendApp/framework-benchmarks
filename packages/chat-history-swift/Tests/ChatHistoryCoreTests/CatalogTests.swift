import Foundation
import Testing

@testable import ChatHistoryCore

@Test func discoversIndexedSessionsAndExcludesSubagents() throws {
  let fileManager = FileManager.default
  let home = fileManager.temporaryDirectory.appending(
    path: "legend-swift-catalog-\(UUID().uuidString)")
  defer { try? fileManager.removeItem(at: home) }
  let codexRoot = home.appending(path: ".codex/sessions")
  let claudeRoot = home.appending(path: ".claude/projects/demo")
  try fileManager.createDirectory(at: codexRoot, withIntermediateDirectories: true)
  try fileManager.createDirectory(at: claudeRoot, withIntermediateDirectories: true)

  let codexId = "11111111-1111-1111-1111-111111111111"
  try "{\"body\":\"catalog must not parse this\"}\n".write(
    to: codexRoot.appending(path: "rollout-2026-01-01-\(codexId).jsonl"),
    atomically: true,
    encoding: .utf8
  )
  try
    "{\"id\":\"\(codexId)\",\"thread_name\":\"Indexed Codex\",\"updated_at\":\"2026-01-01T10:00:00Z\"}\n"
    .write(
      to: home.appending(path: ".codex/session_index.jsonl"),
      atomically: true,
      encoding: .utf8
    )

  let subagentId = "22222222-2222-2222-2222-222222222222"
  try
    "{\"payload\":{\"source\":{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"\(codexId)\"}}}},\"type\":\"session_meta\"}\n"
    .write(
      to: codexRoot.appending(path: "rollout-2026-01-02-\(subagentId).jsonl"),
      atomically: true,
      encoding: .utf8
    )

  let claudeId = "33333333-3333-3333-3333-333333333333"
  let claudePath = claudeRoot.appending(path: "\(claudeId).jsonl")
  try "{\"body\":\"catalog must not parse this either\"}\n".write(
    to: claudePath, atomically: true, encoding: .utf8)
  let index: [String: Any] = [
    "entries": [
      [
        "fullPath": claudePath.path,
        "modified": "2026-01-03T10:00:00Z",
        "sessionId": claudeId,
        "summary": "Indexed Claude",
      ]
    ],
    "version": 1,
  ]
  try JSONSerialization.data(withJSONObject: index).write(
    to: claudeRoot.appending(path: "sessions-index.json"))

  let result = getRecentChats(limit: 20, home: home.path)
  #expect(result.nativeTotalMs >= 0)
  #expect(result.summaries.map(\.title) == ["Indexed Claude", "Indexed Codex"])
  #expect(!result.summaries.contains(where: { $0.id == "codex:\(subagentId)" }))
  #expect(getRecentChats(limit: 0, home: home.path).summaries.isEmpty)
}
