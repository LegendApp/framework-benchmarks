import Foundation

public enum ChatProvider: String, Codable, Sendable {
  case claude
  case codex
}

public struct ChatSummary: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let path: String
  public let provider: ChatProvider
  public let title: String
  public let updatedAt: Double

  public init(id: String, path: String, provider: ChatProvider, title: String, updatedAt: Double) {
    self.id = id
    self.path = path
    self.provider = provider
    self.title = title
    self.updatedAt = updatedAt
  }
}

public struct ChatFileChange: Codable, Equatable, Sendable {
  public var additions: Int
  public var deletions: Int
  public let path: String

  public init(additions: Int, deletions: Int, path: String) {
    self.additions = additions
    self.deletions = deletions
    self.path = path
  }
}

public enum ChatRowKind: String, Codable, Sendable {
  case assistant
  case files
  case tool
  case user
}

public enum ChatToolStatus: String, Codable, Sendable {
  case completed
  case failed
  case unknown
  case none = ""
}

public struct ChatRow: Codable, Identifiable, Sendable {
  public let fileChanges: [ChatFileChange]
  public let hasImagePlaceholder: Bool
  public let id: String
  public let imageSources: [String]
  public let kind: ChatRowKind
  private let eagerMarkdown: String
  let nativeText: NativeRowText?
  public var markdown: String { nativeText?.markdown ?? eagerMarkdown }
  public let toolName: String
  private let eagerToolPreview: String
  public var toolPreview: String { nativeText?.preview ?? eagerToolPreview }
  public let toolStatus: ChatToolStatus

  public init(
    fileChanges: [ChatFileChange],
    hasImagePlaceholder: Bool,
    id: String,
    imageSources: [String],
    kind: ChatRowKind,
    markdown: String,
    toolName: String,
    toolPreview: String,
    toolStatus: ChatToolStatus
  ) {
    self.fileChanges = fileChanges
    self.hasImagePlaceholder = hasImagePlaceholder
    self.id = id
    self.imageSources = imageSources
    self.kind = kind
    self.eagerMarkdown = markdown
    self.nativeText = nil
    self.toolName = toolName
    self.eagerToolPreview = toolPreview
    self.toolStatus = toolStatus
  }

  init(
    fileChanges: [ChatFileChange], hasImagePlaceholder: Bool, id: String,
    imageSources: [String], kind: ChatRowKind, markdown: String, toolName: String,
    toolPreview: String, toolStatus: ChatToolStatus, nativeText: NativeRowText
  ) {
    self.fileChanges = fileChanges
    self.hasImagePlaceholder = hasImagePlaceholder
    self.id = id
    self.imageSources = imageSources
    self.kind = kind
    self.eagerMarkdown = markdown
    self.toolName = toolName
    self.eagerToolPreview = toolPreview
    self.toolStatus = toolStatus
    self.nativeText = nativeText
  }

  private enum CodingKeys: String, CodingKey {
    case fileChanges, hasImagePlaceholder, id, imageSources, kind, markdown
    case toolName, toolPreview, toolStatus
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      fileChanges: try c.decode([ChatFileChange].self, forKey: .fileChanges),
      hasImagePlaceholder: try c.decode(Bool.self, forKey: .hasImagePlaceholder),
      id: try c.decode(String.self, forKey: .id),
      imageSources: try c.decode([String].self, forKey: .imageSources),
      kind: try c.decode(ChatRowKind.self, forKey: .kind),
      markdown: try c.decode(String.self, forKey: .markdown),
      toolName: try c.decode(String.self, forKey: .toolName),
      toolPreview: try c.decode(String.self, forKey: .toolPreview),
      toolStatus: try c.decode(ChatToolStatus.self, forKey: .toolStatus))
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(fileChanges, forKey: .fileChanges)
    try c.encode(hasImagePlaceholder, forKey: .hasImagePlaceholder)
    try c.encode(id, forKey: .id)
    try c.encode(imageSources, forKey: .imageSources)
    try c.encode(kind, forKey: .kind)
    try c.encode(markdown, forKey: .markdown)
    try c.encode(toolName, forKey: .toolName)
    try c.encode(toolPreview, forKey: .toolPreview)
    try c.encode(toolStatus, forKey: .toolStatus)
  }

}

public struct NativeTiming: Codable, Sendable {
  public let loadMs: Double
  public let nativeTotalMs: Double
  public let parseMs: Double
  public let scanMs: Double

  public init(loadMs: Double, nativeTotalMs: Double, parseMs: Double, scanMs: Double) {
    self.loadMs = loadMs
    self.nativeTotalMs = nativeTotalMs
    self.parseMs = parseMs
    self.scanMs = scanMs
  }
}

public struct ChatDocument: Codable, Sendable {
  var nativeStorage: NativeDocumentStorage?
  public var contentDigest: String {
    nativeStorage?.native.contentDigest() ?? normalizedContentDigest(rows)
  }
  private enum CodingKeys: String, CodingKey {
    case path, provider, recordCount, rows, sourceBytes, timing, warningCount
  }
  public let path: String
  public let provider: ChatProvider
  public let recordCount: Int
  public let rows: [ChatRow]
  public let sourceBytes: Int
  public let timing: NativeTiming
  public let warningCount: Int

  public init(
    path: String,
    provider: ChatProvider,
    recordCount: Int,
    rows: [ChatRow],
    sourceBytes: Int,
    timing: NativeTiming,
    warningCount: Int
  ) {
    self.path = path
    self.provider = provider
    self.recordCount = recordCount
    self.rows = rows
    self.sourceBytes = sourceBytes
    self.timing = timing
    self.warningCount = warningCount
  }

  init(
    path: String, provider: ChatProvider, recordCount: Int, rows: [ChatRow],
    sourceBytes: Int, timing: NativeTiming, warningCount: Int,
    nativeStorage: NativeDocumentStorage
  ) {
    self.init(path: path, provider: provider, recordCount: recordCount, rows: rows,
      sourceBytes: sourceBytes, timing: timing, warningCount: warningCount)
    self.nativeStorage = nativeStorage
  }

}

@inline(__always)
private func updateContentDigest<S: Sequence>(_ digest: inout UInt64, _ bytes: S)
where S.Element == UInt8 {
  for byte in bytes {
    digest ^= UInt64(byte)
    digest &*= 0x100000001b3
  }
}

public func normalizedContentDigest(_ rows: [ChatRow]) -> String {
  var digest: UInt64 = 0xcbf29ce484222325
  @inline(__always) func field(_ value: String) {
    let bytes = value.utf8
    updateContentDigest(&digest, String(bytes.count).utf8)
    updateContentDigest(&digest, ":".utf8)
    updateContentDigest(&digest, bytes)
    updateContentDigest(&digest, ";".utf8)
  }
  @inline(__always) func field(_ value: Int) {
    field(String(value))
  }

  field(rows.count)
  for row in rows {
    field(row.kind.rawValue)
    field(row.markdown)
    field(row.toolName)
    field(row.toolPreview)
    field(row.toolStatus.rawValue)
    field(row.hasImagePlaceholder ? 1 : 0)
    field(row.imageSources.count)
    for source in row.imageSources {
      field(source)
    }
    field(row.fileChanges.count)
    for change in row.fileChanges {
      field(change.path)
      field(change.additions)
      field(change.deletions)
    }
  }
  return String(format: "%016llx", digest)
}

public struct CatalogResult: Codable, Sendable {
  public let nativeTotalMs: Double
  public let summaries: [ChatSummary]

  public init(nativeTotalMs: Double, summaries: [ChatSummary]) {
    self.nativeTotalMs = nativeTotalMs
    self.summaries = summaries
  }
}

@inline(__always)
func monotonicMilliseconds() -> Double {
  Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}
