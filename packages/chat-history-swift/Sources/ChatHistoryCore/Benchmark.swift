import Foundation

public struct ChatBenchmarkTarget: Codable, Sendable {
  public let id: String
  public let provider: ChatProvider
}

public struct ChatBenchmarkConfig: Codable, Sendable {
  public let loadImages: Bool
  public let switchDelayMs: Double
  public let targets: [ChatBenchmarkTarget]
  public let version: Int
}

public enum ChatBenchmarkPhase: String, Codable, Sendable {
  case initial
  case `switch`
}

public struct ChatBenchmarkContentReadyEvent: Codable, Sendable {
  public let durationMs: Double
  public let name: String
  public let path: String
  public let phase: ChatBenchmarkPhase
  public let recordCount: Int
  public let rowCount: Int
  public let sourceBytes: Int
  public let timestampMs: Double
  public let timing: NativeTiming

  public init(durationMs: Double, document: ChatDocument, phase: ChatBenchmarkPhase) {
    self.durationMs = durationMs
    self.name = "contentReady"
    self.path = document.path
    self.phase = phase
    self.recordCount = document.recordCount
    self.rowCount = document.rows.count
    self.sourceBytes = document.sourceBytes
    self.timestampMs = Date().timeIntervalSince1970 * 1_000
    self.timing = document.timing
  }
}

public struct ChatBenchmarkContentDigestEvent: Encodable, Sendable {
  public let contentDigest: String
  public let name = "contentDigest"
  public let path: String
  public let phase: ChatBenchmarkPhase
}

public enum ChatBenchmark {
  public static func load(environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> ChatBenchmarkConfig?
  {
    guard let path = environment["CHAT_HISTORY_BENCHMARK_CONFIG"] else { return nil }
    let config = try JSONDecoder().decode(
      ChatBenchmarkConfig.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    guard config.version == 2, config.targets.count == 2 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return config
  }

  public static func emit<T: Encodable>(
    _ event: T, environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    guard let path = environment["CHAT_HISTORY_BENCHMARK_EVENTS"],
      let data = try? JSONEncoder().encode(event)
    else { return }
    let url = URL(fileURLWithPath: path)
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.write(contentsOf: Data([0x0A]))
    } catch {
      return
    }
  }

  public static func emitWindowShown(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    emit(
      WindowShownEvent(name: "windowShown", timestampMs: Date().timeIntervalSince1970 * 1_000),
      environment: environment)
  }

  public static func emitContentDigest(document: ChatDocument, phase: ChatBenchmarkPhase) {
    Task.detached(priority: .utility) {
      emit(
        ChatBenchmarkContentDigestEvent(
          contentDigest: normalizedContentDigest(document.rows),
          path: document.path,
          phase: phase))
    }
  }
}

private struct WindowShownEvent: Codable {
  let name: String
  let timestampMs: Double
}
