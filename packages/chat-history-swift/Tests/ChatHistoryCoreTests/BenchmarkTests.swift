import Foundation
import Testing

@testable import ChatHistoryCore

@Test func loadsBenchmarkManifestAndWritesEvents() throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: "chat-history-benchmark-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let manifest = root.appending(path: "fixtures.json")
  let events = root.appending(path: "events.jsonl")
  let target = """
    {
      "id": "codex:fixture",
      "provider": "codex"
    }
    """
  try """
    {"targets":[\(target),\(target)],"loadImages":false,"switchDelayMs":3000,"topDelayMs":3000,"version":2}
    """.write(to: manifest, atomically: true, encoding: .utf8)
  let environment = [
    "CHAT_HISTORY_BENCHMARK_CONFIG": manifest.path,
    "CHAT_HISTORY_BENCHMARK_EVENTS": events.path,
  ]

  let loaded = try ChatBenchmark.load(environment: environment)
  let config = try #require(loaded)
  #expect(config.targets.count == 2)
  #expect(config.loadImages == false)
  ChatBenchmark.emitWindowShown(environment: environment)

  let line = try String(contentsOf: events, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
  let event = try #require(
    JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
  #expect(event["name"] as? String == "windowShown")
  #expect(event["timestampMs"] as? Double != nil)
}
