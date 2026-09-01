import Foundation
import Testing

@testable import ChatHistoryCore

@MainActor
@Test func normalizesAndPersistsSettings() throws {
  let suiteName = "legend-chat-settings-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = ChatHistorySettings(
    appearance: .dark,
    loadImages: false,
    recentChatLimit: 100,
    restoreSelection: true,
    selectedId: "codex:example",
    showPerformanceMetrics: false
  )
  ChatSettingsStore.save(settings, to: defaults)
  #expect(ChatSettingsStore.load(from: defaults) == settings)

  let normalized = ChatHistorySettings(
    recentChatLimit: 500, restoreSelection: false, selectedId: "ignored")
  #expect(normalized.recentChatLimit == 20)
  #expect(normalized.selectedId == nil)
}
