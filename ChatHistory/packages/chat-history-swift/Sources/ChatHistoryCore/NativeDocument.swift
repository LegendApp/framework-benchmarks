import ChatHistoryNative
import Foundation

/// Native rows are immutable. Text caches are synchronized because the UI and
/// background conformance checks may access the same document concurrently.
final class NativeRowText: @unchecked Sendable {
  private let decodeMarkdown: @Sendable () -> String
  private let decodePreview: @Sendable () -> String
  private let lock = NSLock()
  private var cachedMarkdown: String?
  private var cachedPreview: String?

  init(document: NativeDocumentStorage, index: Int) {
    self.decodeMarkdown = { document.native.markdown(at: UInt(index)) }
    self.decodePreview = { document.native.preview(at: UInt(index)) }
  }

  init(markdown: @escaping @Sendable () -> String, preview: @escaping @Sendable () -> String) {
    decodeMarkdown = markdown
    decodePreview = preview
  }

  var uncachedMarkdown: String { decodeMarkdown() }
  var uncachedPreview: String { decodePreview() }

  var markdown: String {
    lock.withLock {
      if let cachedMarkdown { return cachedMarkdown }
      let value = decodeMarkdown()
      cachedMarkdown = value
      return value
    }
  }

  var preview: String {
    lock.withLock {
      if let cachedPreview { return cachedPreview }
      let value = decodePreview()
      cachedPreview = value
      return value
    }
  }

  var decodedFieldCount: Int {
    lock.withLock { (cachedMarkdown == nil ? 0 : 1) + (cachedPreview == nil ? 0 : 1) }
  }
}

final class NativeDocumentStorage: @unchecked Sendable {
  let native: CHNativeDocument
  init(provider: ChatProvider, path: String) throws {
    native = try CHNativeDocument(provider: provider.rawValue, path: path)
  }
}

public enum ChatParser: String, Sendable {
  case swift, cpp
}

public func openChatFile(provider: ChatProvider, path: String, parser: ChatParser? = nil) throws
  -> ChatDocument
{
  let selected =
    parser ?? ChatParser(
      rawValue: ProcessInfo.processInfo.environment["CHAT_HISTORY_PARSER"] ?? "swift") ?? .swift
  return try selected == .swift
    ? openChatFileSwift(provider: provider, path: path)
    : openChatFileCPP(provider: provider, path: path)
}

func openChatFileCPP(provider: ChatProvider, path: String) throws -> ChatDocument {
  let startedAt = monotonicMilliseconds()
  let storage = try NativeDocumentStorage(provider: provider, path: path)
  let native = storage.native
  let rows = ChatRows(count: Int(native.rowCount)) { index in
    let metadata = storage.native.metadata(at: UInt(index))
    let files = (metadata["files"] as? [[String: Any]] ?? []).map { file in
      ChatFileChange(
        additions: (file["additions"] as? NSNumber)?.intValue ?? 0,
        deletions: (file["deletions"] as? NSNumber)?.intValue ?? 0,
        path: file["path"] as? String ?? "")
    }
    return ChatRow(
      fileChanges: files,
      hasImagePlaceholder: metadata["hasImagePlaceholder"] as? Bool ?? false,
      id: "row:\(index)",
      imageSources: metadata["images"] as? [String] ?? [],
      kind: ChatRowKind(rawValue: metadata["kind"] as? String ?? "")!,
      markdown: "",
      toolName: metadata["toolName"] as? String ?? "",
      toolPreview: "",
      toolStatus: ChatToolStatus(rawValue: metadata["toolStatus"] as? String ?? "") ?? .none,
      nativeText: NativeRowText(document: storage, index: index))
  }
  let totalMs = monotonicMilliseconds() - startedAt
  return ChatDocument(
    path: path, provider: provider, recordCount: Int(native.recordCount), rows: rows,
    sourceBytes: Int(native.sourceBytes),
    timing: NativeTiming(
      loadMs: native.loadMs, nativeTotalMs: totalMs,
      parseMs: totalMs - native.loadMs - native.scanMs, scanMs: native.scanMs),
    warningCount: Int(native.warningCount),
    nativeStorage: storage)
}
