import ChatHistoryNative
import Foundation

/// Native rows are immutable. Text caches are synchronized because the UI and
/// background conformance checks may access the same document concurrently.
final class NativeRowText: @unchecked Sendable {
  let document: NativeDocumentStorage
  let index: Int
  private let lock = NSLock()
  private var cachedMarkdown: String?
  private var cachedPreview: String?

  init(document: NativeDocumentStorage, index: Int) {
    self.document = document
    self.index = index
  }

  var markdown: String {
    lock.withLock {
      if let cachedMarkdown { return cachedMarkdown }
      let value = document.native.markdown(at: UInt(index))
      cachedMarkdown = value
      return value
    }
  }

  var preview: String {
    lock.withLock {
      if let cachedPreview { return cachedPreview }
      let value = document.native.preview(at: UInt(index))
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

public func openChatFile(provider: ChatProvider, path: String) throws -> ChatDocument {
  let startedAt = monotonicMilliseconds()
  let storage = try NativeDocumentStorage(provider: provider, path: path)
  let native = storage.native
  let rows = (0..<Int(native.rowCount)).map { index in
    let metadata = native.metadata(at: UInt(index))
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
