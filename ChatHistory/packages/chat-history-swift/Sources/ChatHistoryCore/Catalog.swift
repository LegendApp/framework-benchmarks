import Foundation

private typealias JSONObject = [String: Any]

private struct CatalogMetadata {
  let title: String
  let updatedAt: Double
}

private struct CatalogCandidate {
  let indexed: Bool
  let summary: ChatSummary
}

private func jsonObject(at path: String) -> JSONObject? {
  guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
  return (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
}

private func jsonlFiles(at root: String) -> [String] {
  let fileManager = FileManager.default
  guard
    let enumerator = fileManager.enumerator(
      at: URL(fileURLWithPath: root),
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
  else { return [] }
  var files: [String] = []
  for case let url as URL in enumerator where url.pathExtension == "jsonl" {
    files.append(url.path)
  }
  return files
}

private func sessionId(for path: String) -> String {
  let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
  return stem.count >= 36 ? String(stem.suffix(36)) : stem
}

private func modifiedAt(_ path: String) -> Double {
  guard
    let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [
      .contentModificationDateKey
    ]),
    let date = values.contentModificationDate
  else { return 0 }
  return date.timeIntervalSince1970 * 1_000
}

private func fallbackTitle(provider: ChatProvider, updatedAt: Double) -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = "MMM d"
  let label =
    updatedAt > 0
    ? formatter.string(from: Date(timeIntervalSince1970: updatedAt / 1_000)) : "Unknown date"
  return "\(provider == .codex ? "Codex" : "Claude") chat — \(label)"
}

private func loadCodexMetadata(home: String) -> [String: CatalogMetadata] {
  let path = URL(fileURLWithPath: home).appending(path: ".codex/session_index.jsonl").path
  guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
  var metadata: [String: CatalogMetadata] = [:]
  for line in source.components(separatedBy: "\n") where !line.isEmpty {
    guard let data = line.data(using: .utf8),
      let record = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject,
      let id = record["id"] as? String
    else { continue }
    metadata[id] = CatalogMetadata(
      title: record["thread_name"] as? String ?? "",
      updatedAt: catalogTimestamp(record["updated_at"])
    )
  }
  return metadata
}

private func loadClaudeMetadata(root: String) -> [String: CatalogMetadata] {
  let fileManager = FileManager.default
  guard
    let enumerator = fileManager.enumerator(
      at: URL(fileURLWithPath: root),
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
  else { return [:] }
  var metadata: [String: CatalogMetadata] = [:]
  for case let url as URL in enumerator where url.lastPathComponent == "sessions-index.json" {
    guard let index = jsonObject(at: url.path), let entries = index["entries"] as? [JSONObject]
    else { continue }
    for entry in entries {
      let value = CatalogMetadata(
        title: entry["summary"] as? String ?? entry["firstPrompt"] as? String ?? "",
        updatedAt: catalogTimestamp(entry["modified"]) != 0
          ? catalogTimestamp(entry["modified"])
          : catalogTimestamp(entry["fileMtime"])
      )
      if let fullPath = entry["fullPath"] as? String, !fullPath.isEmpty {
        metadata[fullPath] = value
      }
      if let id = entry["sessionId"] as? String, !id.isEmpty {
        metadata[id] = value
      }
    }
  }
  return metadata
}

private let fractionalCatalogTimestampStyle = Date.ISO8601FormatStyle(
  includingFractionalSeconds: true)
private let wholeCatalogTimestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

private func catalogTimestamp(_ value: Any?) -> Double {
  if let number = value as? NSNumber { return number.doubleValue }
  guard let source = value as? String else { return 0 }
  if let date = try? Date(source, strategy: fractionalCatalogTimestampStyle) {
    return date.timeIntervalSince1970 * 1_000
  }
  if let date = try? Date(source, strategy: wholeCatalogTimestampStyle) {
    return date.timeIntervalSince1970 * 1_000
  }
  return 0
}

private func isCodexSubagent(_ path: String) -> Bool {
  guard let handle = FileHandle(forReadingAtPath: path) else { return false }
  defer { try? handle.close() }
  guard let data = try? handle.read(upToCount: 64 * 1_024) else { return false }
  // Only the first JSONL record is metadata. Slice bytes before decoding so
  // subsequent message text (or a partial UTF-8 character) is never inspected.
  let firstLine = data.prefix(upTo: data.firstIndex(of: 0x0a) ?? data.endIndex)
  guard let root = (try? JSONSerialization.jsonObject(with: firstLine)) as? JSONObject,
    let payload = root["payload"] as? JSONObject,
    let sourceValue = payload["source"] as? JSONObject
  else { return false }
  return sourceValue["subagent"] != nil
}

private struct BenchmarkCatalog: Decodable {
  let samples: [ChatSummary]?
}

public func getRecentChats(
  limit: Int = 20,
  home: String = NSHomeDirectory(),
  benchmarkConfigPath: String? = ProcessInfo.processInfo.environment["CHAT_HISTORY_BENCHMARK_CONFIG"]
) -> CatalogResult {
  let startedAt = monotonicMilliseconds()
  let boundedLimit = max(0, limit)
  guard boundedLimit > 0 else {
    return CatalogResult(nativeTotalMs: monotonicMilliseconds() - startedAt, summaries: [])
  }
  let homeURL = URL(fileURLWithPath: home)
  let claudeRoot = homeURL.appending(path: ".claude/projects").path
  let codexMetadata = loadCodexMetadata(home: home)
  let claudeMetadata = loadClaudeMetadata(root: claudeRoot)
  let codexFiles =
    jsonlFiles(at: homeURL.appending(path: ".codex/sessions").path)
    + jsonlFiles(at: homeURL.appending(path: ".codex/archived_sessions").path)
  let claudeFiles = jsonlFiles(at: claudeRoot)
  var candidates = codexFiles.map { path in
    let id = sessionId(for: path)
    let metadata = codexMetadata[id]
    let updatedAt = metadata?.updatedAt ?? modifiedAt(path)
    return CatalogCandidate(
      indexed: metadata != nil,
      summary: ChatSummary(
        id: "codex:\(id)",
        path: path,
        provider: .codex,
        title: metadata?.title.isEmpty == false
          ? metadata!.title : fallbackTitle(provider: .codex, updatedAt: updatedAt),
        updatedAt: updatedAt
      )
    )
  }
  candidates += claudeFiles.compactMap { path in
    let url = URL(fileURLWithPath: path)
    guard !url.pathComponents.contains("subagents"), !url.lastPathComponent.hasPrefix("agent-")
    else { return nil }
    let id = sessionId(for: path)
    let metadata = claudeMetadata[path] ?? claudeMetadata[id]
    let updatedAt = metadata?.updatedAt ?? modifiedAt(path)
    return CatalogCandidate(
      indexed: true,
      summary: ChatSummary(
        id: "claude:\(id)",
        path: path,
        provider: .claude,
        title: metadata?.title.isEmpty == false
          ? metadata!.title : fallbackTitle(provider: .claude, updatedAt: updatedAt),
        updatedAt: updatedAt
      )
    )
  }
  if let path = benchmarkConfigPath,
    let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
    let config = try? JSONDecoder().decode(BenchmarkCatalog.self, from: data)
  {
    candidates += (config.samples ?? []).map { CatalogCandidate(indexed: true, summary: $0) }
  }
  candidates.sort {
    $0.summary.updatedAt == $1.summary.updatedAt
      ? $0.summary.id < $1.summary.id
      : $0.summary.updatedAt > $1.summary.updatedAt
  }
  var summaries: [ChatSummary] = []
  var seenIds = Set<String>()
  for candidate in candidates {
    guard seenIds.insert(candidate.summary.id).inserted else { continue }
    if !candidate.indexed, isCodexSubagent(candidate.summary.path) { continue }
    summaries.append(candidate.summary)
    if summaries.count == boundedLimit { break }
  }
  return CatalogResult(nativeTotalMs: monotonicMilliseconds() - startedAt, summaries: summaries)
}
