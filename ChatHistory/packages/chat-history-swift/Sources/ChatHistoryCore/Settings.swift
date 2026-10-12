import Foundation

public enum ChatAppearance: String, CaseIterable, Codable, Sendable {
  case system
  case light
  case dark
}

public struct ChatHistorySettings: Codable, Equatable, Sendable {
  public var appearance: ChatAppearance
  public var loadImages: Bool
  public var recentChatLimit: Int
  public var restoreSelection: Bool
  public var selectedId: String?
  public var showPerformanceMetrics: Bool

  public init(
    appearance: ChatAppearance = .system,
    loadImages: Bool = true,
    recentChatLimit: Int = 20,
    restoreSelection: Bool = true,
    selectedId: String? = nil,
    showPerformanceMetrics: Bool = false
  ) {
    self.appearance = appearance
    self.loadImages = loadImages
    self.recentChatLimit = recentChatLimit
    self.restoreSelection = restoreSelection
    self.selectedId = selectedId
    self.showPerformanceMetrics = showPerformanceMetrics
    normalize()
  }

  public mutating func normalize() {
    if ![20, 50, 100].contains(recentChatLimit) {
      recentChatLimit = 20
    }
    if !restoreSelection {
      selectedId = nil
    }
  }
}

@MainActor
public enum ChatSettingsStore {
  private static let key = "chatHistorySettings"

  public static func load(from defaults: UserDefaults = .standard) -> ChatHistorySettings {
    guard let data = defaults.data(forKey: key),
      var settings = try? JSONDecoder().decode(ChatHistorySettings.self, from: data)
    else {
      return ChatHistorySettings()
    }
    settings.normalize()
    return settings
  }

  public static func save(_ settings: ChatHistorySettings, to defaults: UserDefaults = .standard) {
    var normalized = settings
    normalized.normalize()
    if let data = try? JSONEncoder().encode(normalized) {
      defaults.set(data, forKey: key)
    }
  }
}
