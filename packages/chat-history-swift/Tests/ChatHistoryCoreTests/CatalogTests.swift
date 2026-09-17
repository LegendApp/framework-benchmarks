import Foundation
import Testing

@testable import ChatHistoryCore

@Test func missingProviderDirectoriesReturnAnEmptyCatalog() throws {
  let fileManager = FileManager.default
  let home = fileManager.temporaryDirectory.appending(
    path: "legend-swift-empty-catalog-\(UUID().uuidString)")
  defer { try? fileManager.removeItem(at: home) }
  try fileManager.createDirectory(at: home, withIntermediateDirectories: true)

  #expect(getRecentChats(limit: 20, home: home.path).summaries.isEmpty)
}

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

@Test func codexHeaderDiscoveryIgnoresFollowingBytes() throws {
  let fm = FileManager.default
  let home = fm.temporaryDirectory.appending(path: "legend-header-boundary-\(UUID().uuidString)")
  defer { try? fm.removeItem(at: home) }
  let root = home.appending(path: ".codex/sessions")
  try fm.createDirectory(at: root, withIntermediateDirectories: true)
  let hidden = "44444444-4444-4444-4444-444444444444"
  let visible = "55555555-5555-5555-5555-555555555555"
  // Invalid/truncated UTF-8 in the next record must not invalidate the header.
  var data = Data("{\"payload\":{\"source\":{\"subagent\":{}}}}\n".utf8)
  data.append(contentsOf: [0xff, 0xe2, 0x82])
  try data.write(to: root.appending(path: "rollout-2026-01-01-\(hidden).jsonl"))
  // A later mention of subagent must not hide an ordinary session.
  try Data("{\"payload\":{\"source\":\"cli\"}}\n{\"payload\":{\"source\":{\"subagent\":{}}}}\n".utf8)
    .write(to: root.appending(path: "rollout-2026-01-01-\(visible).jsonl"))
  #expect(getRecentChats(home: home.path).summaries.map(\.id) == ["codex:\(visible)"])
}
