import AppKit
import ChatHistoryCore
import ChatHistoryMarkdown
import SwiftUI

@MainActor
final class ChatHistoryStore: ObservableObject {
  @Published private(set) var catalogMs: Double?
  @Published private(set) var document: ChatDocument?
  @Published private(set) var errorMessage: String?
  @Published private(set) var firstPaintMs: Double?
  @Published private(set) var isLoading = false
  @Published private(set) var selectedId: String?
  @Published private(set) var settings = ChatSettingsStore.load()
  @Published private(set) var summaries: [ChatSummary] = []

  private var generation = 0
  private let benchmarkConfig: ChatBenchmarkConfig?
  private var benchmarkPhase: ChatBenchmarkPhase?
  private var openedAt = 0.0
  private var paintPending = false

  init() {
    benchmarkConfig = try? ChatBenchmark.load()
    if let benchmarkConfig {
      settings = ChatHistorySettings(
        loadImages: benchmarkConfig.loadImages,
        restoreSelection: false)
      summaries = benchmarkConfig.fixtures.map(\.summary)
      catalogMs = 0
      if let initial = summaries.first {
        select(initial, phase: .initial)
      }
    } else {
      Task { await loadCatalog() }
    }
  }

  func loadCatalog(preferredId: String? = nil) async {
    let limit = settings.recentChatLimit
    let result = await Task.detached(priority: .userInitiated) {
      getRecentChats(limit: limit)
    }.value
    summaries = result.summaries
    catalogMs = result.nativeTotalMs
    let restoredId = settings.restoreSelection ? preferredId ?? settings.selectedId : nil
    let initial = summaries.first(where: { $0.id == restoredId }) ?? summaries.first
    if let initial {
      select(initial)
    } else {
      generation += 1
      selectedId = nil
      document = nil
      errorMessage = nil
      firstPaintMs = nil
      isLoading = false
    }
  }

  func select(_ summary: ChatSummary, phase: ChatBenchmarkPhase? = nil) {
    generation += 1
    let currentGeneration = generation
    selectedId = summary.id
    benchmarkPhase = phase
    paintPending = false
    if phase == nil && settings.restoreSelection {
      settings.selectedId = summary.id
      ChatSettingsStore.save(settings)
    }
    document = nil
    errorMessage = nil
    firstPaintMs = nil
    isLoading = true
    openedAt = ProcessInfo.processInfo.systemUptime * 1_000
    Task {
      do {
        let loaded = try await Task.detached(priority: .userInitiated) {
          try openChatFile(provider: summary.provider, path: summary.path)
        }.value
        guard generation == currentGeneration else { return }
        document = loaded
        isLoading = false
      } catch {
        guard generation == currentGeneration else { return }
        errorMessage = error.localizedDescription
        isLoading = false
      }
    }
  }

  func updateSettings(_ value: ChatHistorySettings) {
    var normalized = value
    normalized.normalize()
    let limitChanged = normalized.recentChatLimit != settings.recentChatLimit
    settings = normalized
    ChatSettingsStore.save(normalized)
    if limitChanged {
      Task { await loadCatalog(preferredId: selectedId) }
    }
  }

  func recordFirstPaint(for path: String) {
    guard document?.path == path, firstPaintMs == nil, !paintPending else { return }
    paintPending = true
    DispatchQueue.main.async {
      DispatchQueue.main.async { [weak self] in
        self?.completeFirstPaint(for: path)
      }
    }
  }

  private func completeFirstPaint(for path: String) {
    guard let document, document.path == path, firstPaintMs == nil else { return }
    let durationMs = ProcessInfo.processInfo.systemUptime * 1_000 - openedAt
    firstPaintMs = durationMs
    guard let phase = benchmarkPhase else { return }
    ChatBenchmark.emit(
      ChatBenchmarkContentReadyEvent(durationMs: durationMs, document: document, phase: phase))
    ChatBenchmark.emitContentDigest(document: document, phase: phase)
    if phase == .initial, let benchmarkConfig, benchmarkConfig.fixtures.count == 2 {
      let secondary = benchmarkConfig.fixtures[1].summary
      Task {
        try? await Task.sleep(for: .milliseconds(Int64(benchmarkConfig.switchDelayMs)))
        select(secondary, phase: .switch)
      }
    }
  }
}

@main
struct ChatHistorySwiftUIApp: App {
  var body: some Scene {
    WindowGroup("Legend Chat History") {
      ContentView()
        .frame(minWidth: 640, minHeight: 460)
    }
    .defaultSize(width: 1_280, height: 720)
    .windowToolbarStyle(.unified)
  }
}

struct ContentView: View {
  @StateObject private var store = ChatHistoryStore()
  @State private var settingsOpen = false
  @State private var windowShownEmitted = false

  var body: some View {
    NavigationSplitView {
      Sidebar(store: store)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
    } detail: {
      Group {
        if let document = store.document {
          TranscriptView(
            document: document, firstPaintMs: store.firstPaintMs, settings: store.settings
          ) {
            store.recordFirstPaint(for: document.path)
          }
        } else if let errorMessage = store.errorMessage {
          EmptyState(errorMessage, color: .red)
        } else if store.isLoading {
          EmptyState("Loading and parsing natively…")
        } else if store.catalogMs == nil {
          EmptyState("Scanning recent chats…")
        } else if store.summaries.isEmpty {
          EmptyState("No local Codex or Claude transcripts found.")
        } else {
          EmptyState("Select a conversation")
        }
      }
      .navigationTitle(selectedTitle)
      .navigationSubtitle("SwiftUI")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Text(store.catalogMs.map { "catalog \(formatMs($0)) ms" } ?? "Loading catalog…")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Settings", systemImage: "gearshape") {
            settingsOpen = true
          }
          .labelStyle(.iconOnly)
        }
      }
    }
    .preferredColorScheme(store.settings.appearance.colorScheme)
    .onAppear {
      guard !windowShownEmitted else { return }
      windowShownEmitted = true
      ChatBenchmark.emitWindowShown()
      _ = RichMarkdownRenderer.render("Warmup")
    }
    .sheet(isPresented: $settingsOpen) {
      SettingsSheet(settings: store.settings) { value in
        store.updateSettings(value)
        settingsOpen = false
      } onCancel: {
        settingsOpen = false
      }
    }
  }

  private var selectedTitle: String {
    store.summaries.first(where: { $0.id == store.selectedId })?.title ?? "Legend Chat History"
  }
}

private struct Sidebar: View {
  @ObservedObject var store: ChatHistoryStore

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        providerSection(.codex)
        providerSection(.claude)
      }
      .padding(.horizontal, 8)
    }
    .background(.regularMaterial)
  }

  @ViewBuilder
  private func providerSection(_ provider: ChatProvider) -> some View {
    if provider == .claude { Color.clear.frame(height: 12) }
    Text(provider == .codex ? "Codex" : "Claude")
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    ForEach(store.summaries.filter { $0.provider == provider }) { summary in
      Button {
        store.select(summary)
      } label: {
        HStack(spacing: 8) {
          Text(summary.title).lineLimit(1)
          Spacer(minLength: 4)
          Text(relativeDate(summary.updatedAt))
            .font(.caption2)
            .opacity(0.7)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .frame(height: 34)
      }
      .buttonStyle(.plain)
      .foregroundStyle(store.selectedId == summary.id ? Color.white : Color.primary)
      .background(
        store.selectedId == summary.id ? Color.accentColor : Color.clear,
        in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private func relativeDate(_ timestamp: Double) -> String {
    let elapsedMinutes = max(0, Int((Date().timeIntervalSince1970 - timestamp / 1_000) / 60))
    if elapsedMinutes < 1 { return "now" }
    if elapsedMinutes < 60 { return "\(elapsedMinutes)m" }
    let hours = elapsedMinutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days < 7 { return "\(days)d" }
    return Date(timeIntervalSince1970: timestamp / 1_000).formatted(
      .dateTime.month(.abbreviated).day())
  }
}

private struct TranscriptView: View {
  let document: ChatDocument
  let firstPaintMs: Double?
  let settings: ChatHistorySettings
  let onFirstPaint: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      if settings.showPerformanceMetrics {
        TimingView(document: document, firstPaintMs: firstPaintMs)
        Divider()
      }
      ScrollViewReader { proxy in
        List(document.rows) { row in
          TranscriptRow(loadImages: settings.loadImages, row: row)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            .id(row.id)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .onAppear {
              if row.id == document.rows.last?.id {
                onFirstPaint()
              }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
          if document.rows.isEmpty {
            Color.clear.frame(height: 1).onAppear(perform: onFirstPaint)
          }
        }
        .onAppear {
          if let last = document.rows.last {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }
}

private struct TimingView: View {
  let document: ChatDocument
  let firstPaintMs: Double?

  var body: some View {
    HStack(spacing: 14) {
      metric(String(format: "%.1f KB", Double(document.sourceBytes) / 1_024))
      metric("\(document.recordCount) records")
      metric("\(document.rows.count) rows")
      metric("load \(formatMs(document.timing.loadMs)) ms")
      metric("scan \(formatMs(document.timing.scanMs)) ms")
      metric("parse \(formatMs(document.timing.parseMs)) ms")
      metric("bridge 0.00 ms")
      metric(firstPaintMs.map { "paint \(formatMs($0)) ms" } ?? "paint pending")
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 18)
    .frame(minHeight: 34)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func metric(_ value: String) -> some View {
    Text(value).font(.system(size: 11, design: .monospaced))
  }
}

private struct TranscriptRow: View {
  let loadImages: Bool
  let row: ChatRow

  var body: some View {
    switch row.kind {
    case .files:
      FileChangesRow(row: row)
    case .tool:
      DisclosureGroup(row.toolName) {
        if !row.toolPreview.isEmpty {
          Text(row.toolPreview)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
      }
      .foregroundStyle(.secondary)
      .padding(.horizontal, 22)
      .padding(.vertical, 9)
    case .assistant, .user:
      HStack {
        if row.kind == .user { Spacer(minLength: 80) }
        VStack(alignment: .leading, spacing: 8) {
          if loadImages {
            ForEach(row.imageSources, id: \.self) { source in
              MessageImage(source: source)
            }
          }
          if !row.markdown.isEmpty {
            RichMarkdownText(loadImages: loadImages, markdown: row.markdown)
          }
          if row.hasImagePlaceholder || (!loadImages && !row.imageSources.isEmpty) {
            AttachmentLabel("Image or attachment omitted")
          }
        }
        .padding(row.kind == .user ? 12 : 0)
        .background(
          row.kind == .user ? Color(nsColor: .controlBackgroundColor) : Color.clear,
          in: RoundedRectangle(cornerRadius: 18))
        if row.kind == .assistant { Spacer(minLength: 80) }
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 12)
    }
  }
}

private struct RichMarkdownText: View {
  let loadImages: Bool
  let markdown: String

  var body: some View {
    Text(
      AttributedString(
        RichMarkdownRenderer.render(
          markdown, imagePolicy: loadImages ? .loadLocal : .omit)))
      .textSelection(.enabled)
      .lineSpacing(3)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct MessageImage: View {
  let source: String

  var body: some View {
    if let image = localImage {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: 560, maxHeight: 440)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    } else if let url = URL(string: source), let scheme = url.scheme,
      scheme == "http" || scheme == "https"
    {
      AsyncImage(url: url) { phase in
        if let image = phase.image {
          image.resizable().scaledToFit()
        } else if phase.error != nil {
          AttachmentLabel("Image or attachment unavailable")
        } else {
          ProgressView()
        }
      }
      .frame(maxWidth: 560, maxHeight: 440)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    } else {
      AttachmentLabel("Image or attachment unavailable")
    }
  }

  private var localImage: NSImage? {
    if source.hasPrefix("file://"), let url = URL(string: source) {
      return NSImage(contentsOf: url)
    }
    return source.contains("://") ? nil : NSImage(contentsOfFile: source)
  }
}

private struct FileChangesRow: View {
  @State private var expanded = false
  let row: ChatRow

  var body: some View {
    let additions = row.fileChanges.reduce(0) { $0 + $1.additions }
    let deletions = row.fileChanges.reduce(0) { $0 + $1.deletions }
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "doc.badge.plus")
          .font(.title2)
          .frame(width: 40, height: 40)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 3) {
          Text("Edited \(row.fileChanges.count) \(row.fileChanges.count == 1 ? "file" : "files")")
            .bold()
          HStack(spacing: 8) {
            Text("+\(additions)").foregroundStyle(.green)
            Text("−\(deletions)").foregroundStyle(.red)
          }
        }
        Spacer()
      }
      .padding(14)
      Divider()
      ForEach(expanded ? row.fileChanges : Array(row.fileChanges.prefix(3)), id: \.path) { file in
        HStack {
          Text(file.path).lineLimit(1).textSelection(.enabled)
          Spacer()
          Text("+\(file.additions)").foregroundStyle(.green)
          Text("−\(file.deletions)").foregroundStyle(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
      }
      if row.fileChanges.count > 3 {
        Divider()
        Button(expanded ? "Show less" : "Show \(row.fileChanges.count - 3) more files") {
          expanded.toggle()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary)
      }
    }
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding(.horizontal, 22)
    .padding(.vertical, 10)
  }
}

private struct SettingsSheet: View {
  @State private var draft: ChatHistorySettings
  let onSave: (ChatHistorySettings) -> Void
  let onCancel: () -> Void

  init(
    settings: ChatHistorySettings,
    onSave: @escaping (ChatHistorySettings) -> Void,
    onCancel: @escaping () -> Void
  ) {
    _draft = State(initialValue: settings)
    self.onSave = onSave
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Settings").font(.title2.bold())
      Form {
        Picker("Appearance", selection: $draft.appearance) {
          Text("System").tag(ChatAppearance.system)
          Text("Light").tag(ChatAppearance.light)
          Text("Dark").tag(ChatAppearance.dark)
        }
        Picker("Recent chats", selection: $draft.recentChatLimit) {
          Text("20").tag(20)
          Text("50").tag(50)
          Text("100").tag(100)
        }
        Toggle("Restore the last selected chat", isOn: $draft.restoreSelection)
        Toggle("Load attached images", isOn: $draft.loadImages)
        Toggle("Show performance metrics", isOn: $draft.showPerformanceMetrics)
      }
      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
        Button("Save") { onSave(draft) }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(22)
    .frame(width: 440)
  }
}

private struct AttachmentLabel: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(8)
      .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
  }
}

private struct EmptyState: View {
  let text: String
  let color: Color

  init(_ text: String, color: Color = .secondary) {
    self.text = text
    self.color = color
  }

  var body: some View {
    Text(text)
      .foregroundStyle(color)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension ChatAppearance {
  fileprivate var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

private func formatMs(_ value: Double) -> String {
  String(format: "%.2f", value)
}
