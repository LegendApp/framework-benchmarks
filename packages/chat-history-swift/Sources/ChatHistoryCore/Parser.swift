import Foundation

private struct JSONObject {
  let members: [String: JSONRangeValue]
  let orderedMembers: [(String, JSONRangeValue)]

  init?(_ value: JSONRangeValue) {
    guard let pairs = value.objectMembers else { return nil }
    members = Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    orderedMembers = pairs
  }

  subscript(key: String) -> JSONRangeValue? { members[key] }
  var objectMembers: [(String, JSONRangeValue)] { orderedMembers }
}

private struct WorkingRow {
  var callId = ""
  var endedAtMs: Double
  var fileChanges: [ChatFileChange] = []
  var hasImagePlaceholder = false
  var imageSources: [String] = []
  var kind: ChatRowKind
  var markdown = ""
  var startedAtMs: Double
  var toolName = ""
  var toolPreview = ""
  var toolStatus: ChatToolStatus = .none

  init(kind: ChatRowKind, timestampMs: Double) {
    self.endedAtMs = timestampMs
    self.kind = kind
    self.startedAtMs = timestampMs
  }
}

private struct ClaudeRecord {
  let isSidechain: Bool
  let lineRange: Range<Int>
  let parentUuid: String
  let timestampMs: Double
  let type: String
  let uuid: String
}

private func objectValue(_ value: JSONRangeValue?) -> JSONObject? {
  value.flatMap(JSONObject.init)
}

private func arrayValue(_ value: JSONRangeValue?) -> [JSONRangeValue]? {
  value?.arrayValues
}

private func stringValue(_ value: JSONRangeValue?) -> String {
  value.map { $0.reader.stringValue($0) } ?? ""
}

private func booleanValue(_ value: JSONRangeValue?) -> Bool {
  value.map { $0.reader.boolValue($0) } ?? false
}

private func fixedDigits(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int? {
  guard start + count <= bytes.count else { return nil }
  var result = 0
  for byte in bytes[start..<(start + count)] {
    guard byte >= 48, byte <= 57 else { return nil }
    result = result * 10 + Int(byte - 48)
  }
  return result
}

private func isLeapYear(_ year: Int) -> Bool {
  year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
}

private func daysInMonth(_ year: Int, _ month: Int) -> Int {
  let days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  guard (1...12).contains(month) else { return 0 }
  return days[month - 1] + (month == 2 && isLeapYear(year) ? 1 : 0)
}

private func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int64 {
  let adjustedYear = year - (month <= 2 ? 1 : 0)
  let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
  let yearOfEra = adjustedYear - era * 400
  let adjustedMonth = month > 2 ? month - 3 : month + 9
  let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
  let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
  return Int64(era * 146_097 + dayOfEra - 719_468)
}

private func isoTimestampMilliseconds(_ value: String) -> Double {
  let bytes = Array(value.utf8)
  guard bytes.count >= 19,
    bytes[4] == 45, bytes[7] == 45, bytes[10] == 84, bytes[13] == 58, bytes[16] == 58,
    let year = fixedDigits(bytes, 0, 4),
    let month = fixedDigits(bytes, 5, 2),
    let day = fixedDigits(bytes, 8, 2),
    let hour = fixedDigits(bytes, 11, 2),
    let minute = fixedDigits(bytes, 14, 2),
    let second = fixedDigits(bytes, 17, 2),
    (1...12).contains(month), (1...daysInMonth(year, month)).contains(day),
    (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
  else { return 0 }
  let seconds = daysFromCivil(year, month, day) * 86_400
    + Int64(hour * 3_600 + minute * 60 + second)
  var milliseconds = Double(seconds) * 1_000
  if bytes.count > 20, bytes[19] == 46 {
    var scale = 100.0
    for byte in bytes.dropFirst(20).prefix(3) {
      guard byte >= 48, byte <= 57 else { break }
      milliseconds += Double(byte - 48) * scale
      scale /= 10
    }
  }
  return milliseconds
}

private func timestampValue(_ value: JSONRangeValue?) -> Double {
  if let value, value.kind == .primitive {
    return value.reader.numberValue(value)
  }
  return isoTimestampMilliseconds(stringValue(value))
}

private func joinText(_ parts: [String]) -> String {
  parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
}

private func appendMessage(
  _ rows: inout [WorkingRow],
  kind: ChatRowKind,
  markdownParts: [String],
  imageSources: [String],
  hasImagePlaceholder: Bool,
  timestampMs: Double
) {
  let markdown = joinText(markdownParts)
  guard !markdown.isEmpty || !imageSources.isEmpty || hasImagePlaceholder else { return }
  var row = WorkingRow(kind: kind, timestampMs: timestampMs)
  row.markdown = markdown
  row.imageSources = imageSources
  row.hasImagePlaceholder = hasImagePlaceholder
  rows.append(row)
}

@discardableResult
private func appendTool(
  _ rows: inout [WorkingRow],
  toolRows: inout [String: Int],
  callId: String,
  name: String,
  preview: String,
  timestampMs: Double
) -> Int {
  var row = WorkingRow(kind: .tool, timestampMs: timestampMs)
  row.callId = callId
  row.toolName = name.isEmpty ? "Tool" : name
  row.toolPreview = preview
  row.toolStatus = .unknown
  rows.append(row)
  let index = rows.count - 1
  if !callId.isEmpty {
    toolRows[callId] = index
  }
  return index
}

private func applyToolResult(
  _ rows: inout [WorkingRow],
  toolRows: inout [String: Int],
  callId: String,
  preview: String,
  failed: Bool,
  timestampMs: Double
) {
  let index =
    toolRows[callId]
    ?? appendTool(
      &rows,
      toolRows: &toolRows,
      callId: callId,
      name: "Tool",
      preview: "",
      timestampMs: timestampMs
    )
  rows[index].toolStatus = failed ? .failed : .completed
  rows[index].endedAtMs = max(rows[index].endedAtMs, timestampMs)
  if !preview.isEmpty {
    rows[index].toolPreview = preview
  }
}

private func countLines(_ content: String) -> Int {
  guard !content.isEmpty else { return 0 }
  return content.components(separatedBy: "\n").count - (content.hasSuffix("\n") ? 1 : 0)
}

private func countDiffLines(_ diff: String) -> (additions: Int, deletions: Int) {
  var additions = 0
  var deletions = 0
  var inHunk = false
  for line in diff.components(separatedBy: "\n") {
    if line.hasPrefix("@@") {
      inHunk = true
    } else if inHunk && line.hasPrefix("+") {
      additions += 1
    } else if inHunk && line.hasPrefix("-") {
      deletions += 1
    }
  }
  return (additions, deletions)
}

private func visibleUserMarkdown(_ markdown: String, row: WorkingRow) -> String {
  guard row.kind == .user, !row.imageSources.isEmpty || row.hasImagePlaceholder else {
    return markdown
  }
  let trimmedStart = markdown.drop(while: { $0 == "\r" || $0 == "\n" })
  let filesHeading = "# Files mentioned by the user:"
  let requestHeading = "## My request for Codex:"
  guard trimmedStart.hasPrefix(filesHeading),
    let requestRange = trimmedStart.range(of: requestHeading)
  else {
    return markdown
  }
  return String(trimmedStart[requestRange.upperBound...].drop(while: { $0 == "\r" || $0 == "\n" }))
}

private let hiddenDirectivePrefixes = [
  "::git-stage{", "::git-commit{", "::git-create-branch{", "::git-push{",
  "::git-create-pr{", "::created-thread{", "::code-comment{",
]

private func visibleAssistantMarkdown(_ markdown: String, kind: ChatRowKind) -> String {
  guard kind == .assistant else { return markdown }
  var output: [String] = []
  var inCodeFence = false
  var inMemoryCitation = false
  for line in markdown.components(separatedBy: "\n") {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if !inCodeFence && trimmed.hasPrefix("<oai-mem-citation>") {
      inMemoryCitation = !trimmed.contains("</oai-mem-citation>")
    } else if inMemoryCitation {
      inMemoryCitation = !trimmed.contains("</oai-mem-citation>")
    } else if inCodeFence || !hiddenDirectivePrefixes.contains(where: trimmed.hasPrefix) {
      output.append(line)
    }
    if !inMemoryCitation && (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")) {
      inCodeFence.toggle()
    }
  }
  while output.last == "" || output.last == "\r" {
    output.removeLast()
  }
  return output.joined(separator: "\n")
}

private func toolActivityLabel(_ row: WorkingRow) -> String {
  let name = row.toolName.lowercased()
  let label: String
  if ["exec", "shell", "command", "bash"].contains(where: name.contains) {
    label = "Ran a command"
  } else if name.contains("agent") {
    label = "Worked with an agent"
  } else if ["patch", "write", "edit"].contains(where: name.contains) {
    label = "Edited files"
  } else if ["read", "open", "find", "glob", "grep"].contains(where: name.contains) {
    label = "Read files"
  } else if ["web", "search", "browser"].contains(where: name.contains) {
    label = "Searched the web"
  } else if name.contains("image") {
    label = "Created an image"
  } else if !name.isEmpty {
    label =
      "Used \(name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "))"
  } else {
    label = "Used a tool"
  }
  return row.toolStatus == .failed ? "\(label) (failed)" : label
}

private func workLabel(_ rows: ArraySlice<WorkingRow>) -> String {
  let starts = rows.map(\.startedAtMs).filter { $0 > 0 }
  let ends = rows.map(\.endedAtMs).filter { $0 > 0 }
  guard let first = starts.min(), let last = ends.max() else { return "Worked" }
  let elapsed = max(1, Int(((last - first) / 1_000).rounded()))
  let hours = elapsed / 3_600
  let minutes = (elapsed % 3_600) / 60
  let seconds = elapsed % 60
  let duration: String
  if hours > 0 {
    duration = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
  } else if minutes > 0 {
    duration = seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
  } else {
    duration = "\(seconds)s"
  }
  return "Worked for \(duration)"
}

private func workPreview(_ rows: ArraySlice<WorkingRow>) -> String {
  var output: [String] = []
  var activities: [String] = []
  func normalizedActivities(_ values: [String]) -> String {
    values.enumerated().map { index, value in
      guard index > 0, let first = value.first else { return value }
      return first.lowercased() + value.dropFirst()
    }.joined(separator: ", ")
  }
  func appendActivities() {
    if !activities.isEmpty {
      output.append(normalizedActivities(activities))
      activities.removeAll(keepingCapacity: true)
    }
  }
  for row in rows {
    if row.kind == .tool {
      let activity = toolActivityLabel(row)
      if !activities.contains(activity) {
        activities.append(activity)
      }
    } else {
      appendActivities()
      if !row.markdown.isEmpty {
        output.append(String(row.markdown.prefix(4 * 1_024)))
      }
      if row.hasImagePlaceholder {
        output.append("Image or attachment omitted")
      }
    }
  }
  appendActivities()
  return String(output.joined(separator: "\n\n").prefix(64 * 1_024))
}

private func finalizeRow(_ row: WorkingRow, index: Int) -> ChatRow {
  let userVisible = visibleUserMarkdown(row.markdown, row: row)
  return ChatRow(
    fileChanges: row.fileChanges,
    hasImagePlaceholder: row.hasImagePlaceholder,
    id: "row:\(index)",
    imageSources: row.imageSources,
    kind: row.kind,
    markdown: visibleAssistantMarkdown(userVisible, kind: row.kind),
    toolName: row.toolName,
    toolPreview: row.toolPreview,
    toolStatus: row.toolStatus
  )
}

private func displayRows(_ rows: [WorkingRow]) -> [ChatRow] {
  var result: [ChatRow] = []
  var sourceIndex = 0
  while sourceIndex < rows.count {
    let row = rows[sourceIndex]
    if row.kind == .user {
      result.append(finalizeRow(row, index: result.count))
      sourceIndex += 1
      continue
    }
    var turnEnd = sourceIndex
    var lastTool = -1
    while turnEnd < rows.count, rows[turnEnd].kind != .user {
      if rows[turnEnd].kind == .tool {
        lastTool = turnEnd
      }
      turnEnd += 1
    }
    if lastTool >= sourceIndex {
      let grouped = rows[sourceIndex...lastTool]
      var work = WorkingRow(kind: .tool, timestampMs: 0)
      work.toolName = workLabel(grouped)
      work.toolPreview = workPreview(grouped)
      if grouped.contains(where: { $0.kind == .tool && $0.toolStatus == .failed }) {
        work.toolStatus = .failed
      } else if grouped.contains(where: { $0.kind == .tool && $0.toolStatus != .completed }) {
        work.toolStatus = .unknown
      } else {
        work.toolStatus = .completed
      }
      result.append(finalizeRow(work, index: result.count))
      sourceIndex = lastTool + 1
    } else {
      result.append(finalizeRow(row, index: result.count))
      sourceIndex += 1
    }
  }
  return result
}

private func scanLines(_ source: Data) -> [Range<Int>] {
  source.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [Range<Int>] in
    guard let baseAddress = bytes.baseAddress else { return [] }
    var lines: [Range<Int>] = []
    lines.reserveCapacity(max(1, source.count / 8_192))
    var lineStart = 0
    while lineStart < bytes.count {
      let remaining = bytes.count - lineStart
      let newline = memchr(baseAddress.advanced(by: lineStart), 10, remaining)
      let rawEnd = newline.map { baseAddress.distance(to: UnsafeRawPointer($0)) } ?? bytes.count
      let lineEnd = rawEnd > lineStart && bytes[rawEnd - 1] == 13 ? rawEnd - 1 : rawEnd
      if lineEnd > lineStart {
        lines.append(lineStart..<lineEnd)
      }
      lineStart = rawEnd == bytes.count ? bytes.count : rawEnd + 1
    }
    return lines
  }
}

private func parseJSONLine(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) -> JSONObject? {
  JSONRangeReader(bytes: bytes).topLevelObject(range).flatMap(JSONObject.init)
}

private func parseCodex(
  _ bytes: UnsafeRawBufferPointer,
  lines: [Range<Int>]
) -> (rows: [ChatRow], warningCount: Int) {
  var rows: [WorkingRow] = []
  var toolRows: [String: Int] = [:]
  var warningCount = 0
  var cwd = ""
  var sawEventUserMessage = false
  var pendingTurnId = ""
  var pendingFiles: [ChatFileChange] = []
  func appendFiles() {
    if !pendingFiles.isEmpty {
      var row = WorkingRow(kind: .files, timestampMs: 0)
      row.fileChanges = pendingFiles
      rows.append(row)
    }
    pendingTurnId = ""
    pendingFiles.removeAll(keepingCapacity: true)
  }

  for line in lines {
    guard let root = parseJSONLine(bytes, range: line) else {
      warningCount += 1
      continue
    }
    let recordType = stringValue(root["type"])
    let payload = objectValue(root["payload"])
    let timestampMs = timestampValue(root["timestamp"])
    if recordType.isEmpty || root["payload"] == nil {
      warningCount += 1
      continue
    }
    if recordType == "compacted" { continue }
    if recordType == "session_meta" || recordType == "turn_context", let payload {
      let nextCwd = stringValue(payload["cwd"])
      if !nextCwd.isEmpty { cwd = nextCwd }
      continue
    }
    if recordType == "event_msg", let payload {
      let eventType = stringValue(payload["type"])
      if eventType == "user_message" {
        sawEventUserMessage = true
        appendFiles()
        let message = stringValue(payload["message"])
        if message.isEmpty { warningCount += 1 }
        let localImages = (arrayValue(payload["local_images"]) ?? []).map(stringValue).filter {
          !$0.isEmpty
        }
        var hasImagePlaceholder = false
        let remoteImages = (arrayValue(payload["images"]) ?? []).compactMap { value -> String? in
          let image = stringValue(value)
          if image.isEmpty || image.utf8.count > 8 * 1_024 {
            hasImagePlaceholder = true
            return nil
          }
          return image
        }
        appendMessage(
          &rows,
          kind: .user,
          markdownParts: [message],
          imageSources: localImages + remoteImages,
          hasImagePlaceholder: hasImagePlaceholder,
          timestampMs: timestampMs
        )
      } else if eventType == "patch_apply_end", booleanValue(payload["success"]) {
        let turnId = stringValue(payload["turn_id"])
        if !pendingTurnId.isEmpty, !turnId.isEmpty, pendingTurnId != turnId {
          appendFiles()
        }
        pendingTurnId = turnId
        if let changes = objectValue(payload["changes"]) {
          for (path, rawChange) in changes.objectMembers {
            guard let change = objectValue(rawChange) else {
              warningCount += 1
              continue
            }
            let type = stringValue(change["type"])
            let additions: Int
            let deletions: Int
            if type == "update", change["unified_diff"]?.kind == .string {
              (additions, deletions) = countDiffLines(stringValue(change["unified_diff"]))
            } else if type == "add" || type == "delete", change["content"]?.kind == .string {
              let content = stringValue(change["content"])
              let count = countLines(content)
              additions = type == "add" ? count : 0
              deletions = type == "delete" ? count : 0
            } else {
              warningCount += 1
              continue
            }
            let prefix = cwd.isEmpty ? "" : cwd + "/"
            let relativePath =
              !prefix.isEmpty && path.hasPrefix(prefix)
              ? String(path.dropFirst(prefix.count)) : path
            if let index = pendingFiles.firstIndex(where: { $0.path == relativePath }) {
              pendingFiles[index].additions += additions
              pendingFiles[index].deletions += deletions
            } else {
              pendingFiles.append(
                ChatFileChange(additions: additions, deletions: deletions, path: relativePath))
            }
          }
        }
      }
      continue
    }
    guard recordType == "response_item" else { continue }
    guard let payload else {
      warningCount += 1
      continue
    }
    let payloadType = stringValue(payload["type"])
    if payloadType == "message" {
      let role = stringValue(payload["role"])
      if role != "assistant" && (role != "user" || sawEventUserMessage) { continue }
      var text: [String] = []
      var hasImage = false
      if payload["content"]?.kind == .string {
        text.append(stringValue(payload["content"]))
      } else if let content = arrayValue(payload["content"]) {
        for rawBlock in content {
          let block = objectValue(rawBlock)
          let blockType = stringValue(block?["type"])
          if let block, ["input_text", "output_text", "text"].contains(blockType) {
            text.append(stringValue(block["text"]))
          } else if ["input_image", "image"].contains(blockType) {
            hasImage = true
          } else if !blockType.isEmpty {
            warningCount += 1
          }
        }
      } else if payload["content"] != nil {
        warningCount += 1
      }
      appendMessage(
        &rows,
        kind: role == "user" ? .user : .assistant,
        markdownParts: text,
        imageSources: [],
        hasImagePlaceholder: hasImage,
        timestampMs: timestampMs
      )
    } else if ["function_call", "custom_tool_call", "local_shell_call"].contains(payloadType) {
      _ = appendTool(
        &rows,
        toolRows: &toolRows,
        callId: stringValue(payload["call_id"]),
        name: stringValue(payload["name"]),
        preview: stringValue(payload[payloadType == "custom_tool_call" ? "input" : "arguments"]),
        timestampMs: timestampMs
      )
    } else if ["function_call_output", "custom_tool_call_output"].contains(payloadType) {
      applyToolResult(
        &rows,
        toolRows: &toolRows,
        callId: stringValue(payload["call_id"]),
        preview: stringValue(payload["output"]),
        failed: false,
        timestampMs: timestampMs
      )
    } else if payloadType == "image_generation_call" {
      let callId = stringValue(payload["id"])
      let index =
        toolRows[callId]
        ?? appendTool(
          &rows,
          toolRows: &toolRows,
          callId: callId,
          name: "Image generation",
          preview: "",
          timestampMs: timestampMs
        )
      let hasResult = !stringValue(payload["result"]).isEmpty
      rows[index].toolStatus =
        stringValue(payload["status"]) == "failed" ? .failed : hasResult ? .completed : .unknown
      rows[index].hasImagePlaceholder = rows[index].hasImagePlaceholder || hasResult
      rows[index].endedAtMs = max(rows[index].endedAtMs, timestampMs)
    } else if payloadType != "reasoning", !payloadType.isEmpty {
      warningCount += 1
    }
  }
  appendFiles()
  return (displayRows(rows), warningCount)
}

private func parseClaudeMessage(
  _ record: ClaudeRecord,
  root: JSONObject,
  rows: inout [WorkingRow],
  toolRows: inout [String: Int]
) -> Int {
  guard let message = objectValue(root["message"]), message["content"] != nil else {
    return 1
  }
  let kind: ChatRowKind = record.type == "user" ? .user : .assistant
  if message["content"]?.kind == .string {
    appendMessage(
      &rows, kind: kind, markdownParts: [stringValue(message["content"])], imageSources: [],
      hasImagePlaceholder: false,
      timestampMs: record.timestampMs)
    return 0
  }
  guard let content = arrayValue(message["content"]) else { return 1 }
  var text: [String] = []
  var hasImage = false
  var warningCount = 0
  enum DeferredTool {
    case call(id: String, name: String)
    case result(id: String, preview: String, failed: Bool, hasImage: Bool)
  }
  var deferredTools: [DeferredTool] = []
  for rawBlock in content {
    guard let block = objectValue(rawBlock) else {
      warningCount += 1
      continue
    }
    let blockType = stringValue(block["type"])
    if blockType == "text" {
      text.append(stringValue(block["text"]))
    } else if blockType == "image" || blockType == "document" {
      hasImage = true
    } else if blockType == "tool_use" {
      deferredTools.append(.call(id: stringValue(block["id"]), name: stringValue(block["name"])))
    } else if blockType == "tool_result" {
      var previews: [String] = []
      var resultImage = false
      if block["content"]?.kind == .string {
        previews.append(stringValue(block["content"]))
      } else if let resultContent = arrayValue(block["content"]) {
        for rawResult in resultContent {
          if rawResult.kind == .string {
            previews.append(stringValue(rawResult))
          } else {
            let result = objectValue(rawResult)
            let resultType = stringValue(result?["type"])
            if resultType == "text" {
              previews.append(stringValue(result?["text"]))
            } else if resultType == "image" {
              resultImage = true
            } else {
              warningCount += 1
            }
          }
        }
      }
      deferredTools.append(
        .result(
          id: stringValue(block["tool_use_id"]),
          preview: joinText(previews),
          failed: booleanValue(block["is_error"]),
          hasImage: resultImage
        ))
    } else if blockType != "thinking" {
      warningCount += 1
    }
  }
  appendMessage(
    &rows, kind: kind, markdownParts: text, imageSources: [], hasImagePlaceholder: hasImage,
    timestampMs: record.timestampMs)
  for tool in deferredTools {
    switch tool {
    case .call(let id, let name):
      _ = appendTool(
        &rows, toolRows: &toolRows, callId: id, name: name, preview: "",
        timestampMs: record.timestampMs)
    case .result(let id, let preview, let failed, let resultImage):
      applyToolResult(
        &rows, toolRows: &toolRows, callId: id, preview: preview, failed: failed,
        timestampMs: record.timestampMs)
      if resultImage, let index = toolRows[id] {
        rows[index].hasImagePlaceholder = true
      }
    }
  }
  return warningCount
}

private func parseClaude(
  _ bytes: UnsafeRawBufferPointer,
  lines: [Range<Int>]
) -> (rows: [ChatRow], warningCount: Int) {
  var records: [ClaudeRecord] = []
  var recordById: [String: ClaudeRecord] = [:]
  var warningCount = 0
  var leafId = ""
  for line in lines {
    guard let root = parseJSONLine(bytes, range: line) else {
      warningCount += 1
      continue
    }
    let record = ClaudeRecord(
      isSidechain: booleanValue(root["isSidechain"]),
      lineRange: line,
      parentUuid: stringValue(root["parentUuid"]),
      timestampMs: timestampValue(root["timestamp"]),
      type: stringValue(root["type"]),
      uuid: stringValue(root["uuid"])
    )
    records.append(record)
    if !record.uuid.isEmpty, !record.isSidechain {
      recordById[record.uuid] = record
      leafId = record.uuid
    }
  }
  var mainChain = Set<String>()
  var cursor = leafId
  while !cursor.isEmpty, !mainChain.contains(cursor) {
    mainChain.insert(cursor)
    guard let record = recordById[cursor] else {
      warningCount += 1
      break
    }
    cursor = record.parentUuid
  }
  var rows: [WorkingRow] = []
  var toolRows: [String: Int] = [:]
  for record in records where !record.isSidechain && mainChain.contains(record.uuid) {
    if (record.type == "user" || record.type == "assistant"),
      let root = parseJSONLine(bytes, range: record.lineRange)
    {
      warningCount += parseClaudeMessage(record, root: root, rows: &rows, toolRows: &toolRows)
    }
  }
  return (displayRows(rows), warningCount)
}

public struct ParsedChat: Sendable {
  public let parseMs: Double
  public let recordCount: Int
  public let rows: [ChatRow]
  public let scanMs: Double
  public let warningCount: Int
}

private func parseChatData(provider: ChatProvider, source: Data) -> ParsedChat {
  let scanStartedAt = monotonicMilliseconds()
  let lines = scanLines(source)
  let scanMs = monotonicMilliseconds() - scanStartedAt
  let parseStartedAt = monotonicMilliseconds()
  let parsed = source.withUnsafeBytes { bytes in
    provider == .codex ? parseCodex(bytes, lines: lines) : parseClaude(bytes, lines: lines)
  }
  return ParsedChat(
    parseMs: monotonicMilliseconds() - parseStartedAt,
    recordCount: lines.count,
    rows: parsed.rows,
    scanMs: scanMs,
    warningCount: parsed.warningCount
  )
}

public func parseChatText(provider: ChatProvider, text: String) -> ParsedChat {
  parseChatData(provider: provider, source: Data(text.utf8))
}

public func openChatFile(provider: ChatProvider, path: String) throws -> ChatDocument {
  let startedAt = monotonicMilliseconds()
  let loadStartedAt = monotonicMilliseconds()
  let source = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
  let loadMs = monotonicMilliseconds() - loadStartedAt
  let parsed = parseChatData(provider: provider, source: source)
  return ChatDocument(
    contentDigest: normalizedContentDigest(parsed.rows),
    path: path,
    provider: provider,
    recordCount: parsed.recordCount,
    rows: parsed.rows,
    sourceBytes: source.count,
    timing: NativeTiming(
      loadMs: loadMs,
      nativeTotalMs: monotonicMilliseconds() - startedAt,
      parseMs: parsed.parseMs,
      scanMs: parsed.scanMs
    ),
    warningCount: parsed.warningCount
  )
}
