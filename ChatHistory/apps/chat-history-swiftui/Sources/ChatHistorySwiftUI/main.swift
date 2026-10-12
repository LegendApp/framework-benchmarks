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
  private var benchmarkDiscoveryMs: Double?
  private var benchmarkPhase: ChatBenchmarkPhase?
  private var openedAt = 0.0
  private var paintPending = false
  private var topPaintPending = false

  var usesBenchmarkViewport: Bool { benchmarkConfig != nil }

  var benchmarkTopDelayMs: Double? {
    benchmarkPhase == .initial ? benchmarkConfig?.topDelayMs : nil
  }

  init() {
    benchmarkConfig = try? ChatBenchmark.load()
    if let benchmarkConfig {
      settings = ChatHistorySettings(
        loadImages: benchmarkConfig.loadImages,
        restoreSelection: false)
    }
    Task { await loadCatalog() }
  }

  func loadCatalog(preferredId: String? = nil) async {
    let limit = benchmarkConfig == nil ? settings.recentChatLimit : Int.max
    // Synthetic visual fixtures are isolated from the real history catalog.
    let home = benchmarkConfig == nil ? NSHomeDirectory()
      : ProcessInfo.processInfo.environment["CHAT_HISTORY_BENCHMARK_HOME"] ?? NSHomeDirectory()
    let discoveryStartedAt = ProcessInfo.processInfo.systemUptime * 1_000
    let result = await Task.detached(priority: .userInitiated) {
      getRecentChats(limit: limit, home: home)
    }.value
    if let benchmarkConfig {
      benchmarkDiscoveryMs = ProcessInfo.processInfo.systemUptime * 1_000 - discoveryStartedAt
      let targets = benchmarkConfig.targets.compactMap { target in
        result.summaries.first { $0.id == target.id && $0.provider == target.provider }
      }
      guard targets.count == benchmarkConfig.targets.count else {
        catalogMs = result.nativeTotalMs
        errorMessage = "A pinned benchmark chat was not found during native history discovery"
        isLoading = false
        return
      }
      summaries = Array(result.summaries.prefix(settings.recentChatLimit))
      for target in targets where !summaries.contains(where: { $0.id == target.id }) {
        summaries.append(target)
      }
      catalogMs = result.nativeTotalMs
      select(targets[0], phase: .initial)
      return
    }
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
    topPaintPending = false
    if phase == nil && settings.restoreSelection {
      settings.selectedId = summary.id
      ChatSettingsStore.save(settings)
    }
    document = nil
    errorMessage = nil
    firstPaintMs = nil
    isLoading = true
    openedAt = ProcessInfo.processInfo.systemUptime * 1_000
    // Start disk/parsing work before the main actor processes loading-state updates.
    let loadingTask = Task.detached(priority: .userInitiated) {
      try openChatFile(provider: summary.provider, path: summary.path)
    }
    Task {
      do {
        let loaded = try await loadingTask.value
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
      ChatBenchmarkContentReadyEvent(
        discoveryMs: phase == .initial ? benchmarkDiscoveryMs : nil,
        durationMs: durationMs,
        document: document,
        phase: phase))
    ChatBenchmark.emitContentDigest(document: document, phase: phase)
  }

  func recordTopPaint(for path: String, startedAt: Double) {
    guard document?.path == path, benchmarkPhase == .initial, !topPaintPending else { return }
    topPaintPending = true
    let durationMs = ProcessInfo.processInfo.systemUptime * 1_000 - startedAt
    ChatBenchmark.emit(ChatBenchmarkViewportReadyEvent(durationMs: durationMs, path: path))
    if let benchmarkConfig, benchmarkConfig.targets.count == 2,
      let secondary = summaries.first(where: {
        $0.id == benchmarkConfig.targets[1].id && $0.provider == benchmarkConfig.targets[1].provider
      })
    {
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
    .commands { ChatHistoryCommands() }
  }
}

private struct ChatSettingsActionKey: FocusedValueKey {
  typealias Value = () -> Void
}
private extension FocusedValues {
  var showChatSettings: (() -> Void)? {
    get { self[ChatSettingsActionKey.self] }
    set { self[ChatSettingsActionKey.self] = newValue }
  }
}
private struct ChatHistoryCommands: Commands {
  @FocusedValue(\.showChatSettings) private var showSettings
  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") { showSettings?() }.keyboardShortcut(",")
    }
  }
}

struct ContentView: View {
  @StateObject private var store = ChatHistoryStore()
  @StateObject private var demo = ChatDemo()
  @State private var composerText = ""
  @State private var settingsOpen = false
  @State private var windowShownEmitted = false

  var body: some View {
    NavigationSplitView {
      Sidebar(store: store)
        .navigationSplitViewColumnWidth(
          min: store.usesBenchmarkViewport ? TranscriptStyle.benchmarkSidebarPaneWidth : 220,
          ideal: store.usesBenchmarkViewport ? TranscriptStyle.benchmarkSidebarPaneWidth : 260,
          max: store.usesBenchmarkViewport ? TranscriptStyle.benchmarkSidebarPaneWidth : 360)
    } detail: {
      Group {
        if let document = store.document {
          TranscriptView(
            document: document, firstPaintMs: store.firstPaintMs, settings: store.settings,
            topDelayMs: store.benchmarkTopDelayMs,
            onFirstPaint: { store.recordFirstPaint(for: document.path) },
            onTopPaint: { store.recordTopPaint(for: document.path, startedAt: $0) },
            demo: demo)
            // A new document must not inherit the previous list's layout and scroll state.
            .id(document.path)
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
      .overlay(alignment: .bottom) {
        HStack(alignment: .bottom, spacing: 12) {
          TextField("Send a test message that doesn't actually do anything", text: $composerText)
            .textFieldStyle(.plain).font(.system(size: 15)).frame(minHeight: 36)
            .onSubmit(sendDemo)
          Button(action: sendDemo) {
            Text("↑").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
              .frame(width: 36, height: 36)
          }
            .buttonStyle(.plain).background(Color(nsColor: TranscriptColors.primary), in: Circle())
            .opacity(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.3 : 1)
            .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background { TranscriptGlass() }
        .frame(maxWidth: 860).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
      }
      .overlay(alignment: .top) {
        TranscriptGlass(titlebar: true).frame(height: 52).ignoresSafeArea(edges: .top)
          .allowsHitTesting(false)
      }
      .onChange(of: store.selectedId) { _, _ in
        demo.reset()
        composerText = ""
      }
      .background(Color(nsColor: TranscriptColors.background))
      .navigationTitle(selectedTitle)
      .navigationSubtitle("")
      .toolbarBackground(.hidden, for: .windowToolbar)
      .focusedSceneValue(\.showChatSettings, { settingsOpen = true })
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

  private func sendDemo() {
    guard store.document != nil else { return }
    demo.send(composerText)
    composerText = ""
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
    .background(Color(nsColor: TranscriptColors.surfaceMuted))
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
        HStack(spacing: 4) {
          Text(summary.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Spacer(minLength: 4)
          Text(relativeDate(summary.updatedAt))
            .font(.system(size: 11))
            .foregroundStyle(store.selectedId == summary.id ? Color.white.opacity(0.7) : Color(nsColor: TranscriptColors.muted))
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .frame(height: 34)
      }
      .buttonStyle(.plain)
      .foregroundStyle(store.selectedId == summary.id ? Color.white : Color(nsColor: TranscriptColors.foreground))
      .background(
        store.selectedId == summary.id ? Color(nsColor: TranscriptColors.primary) : Color.clear,
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
  let topDelayMs: Double?
  let onFirstPaint: () -> Void
  let onTopPaint: (Double) -> Void
  @ObservedObject var demo: ChatDemo
  private var rows: ChatRows { document.rows.appending(demo.rows) }
  @State private var markdownCache = TranscriptMarkdownCache()
  @State private var topPaintReported = false
  @State private var topStartedAt: Double?

  var body: some View {
    VStack(spacing: 0) {
      if settings.showPerformanceMetrics {
        TimingView(document: document, firstPaintMs: firstPaintMs)
        Divider()
      }
      ScrollViewReader { proxy in
        List {
          ForEach(rows.indices, id: \.self) { index in
            LazyTranscriptRow(
              loadImages: settings.loadImages, rows: rows, index: index, markdownCache: markdownCache
            )
            .padding(.top, index == 0 ? 64 : 0)
            .padding(.bottom, index == rows.count - 1 ? TranscriptStyle.composerHeight + TranscriptStyle.bottomGap : 0)
            .id(index)
            // Plain macOS List retains an eight-point cell gutter. Rows own their insets.
            .padding(.horizontal, -8)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .onAppear {
              if index == document.rows.count - 1 {
                onFirstPaint()
              }
              if index == 0, let topStartedAt, !topPaintReported {
                topPaintReported = true
                DispatchQueue.main.async {
                  DispatchQueue.main.async {
                    onTopPaint(topStartedAt)
                  }
                }
              }
            }
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(edges: .top)
        .overlay {
          if document.rows.isEmpty {
            Color.clear.frame(height: 1).onAppear(perform: onFirstPaint)
          }
        }
        .task(id: document.path) {
          // Resolve the row target after the new list has entered layout.
          await Task.yield()
          guard !Task.isCancelled else { return }
          if let last = rows.indices.last { proxy.scrollTo(last, anchor: .bottom) }
        }
        .onChange(of: demo.rows.last?.markdown) { _, _ in
          if let last = rows.indices.last { proxy.scrollTo(last, anchor: .bottom) }
        }
        .task(id: firstPaintMs) {
          guard firstPaintMs != nil, let topDelayMs, !document.rows.isEmpty else { return }
          try? await Task.sleep(for: .milliseconds(Int64(topDelayMs)))
          guard !Task.isCancelled else { return }
          topStartedAt = ProcessInfo.processInfo.systemUptime * 1_000
          proxy.scrollTo(0, anchor: .top)
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
  let markdownCache: TranscriptMarkdownCache
  @State private var toolExpanded = false

  var body: some View {
    switch row.kind {
    case .files:
      FileChangesRow(row: row)
    case .tool:
      VStack(alignment: .leading, spacing: 16) {
        Button {
          toolExpanded.toggle()
        } label: {
          HStack(spacing: 8) {
            Text(row.toolName).font(.system(size: 14, weight: .medium))
            Text(toolExpanded ? "⌄" : "›").font(.system(size: 18))
            Spacer(minLength: 0)
          }.frame(height: 20)
        }
        .buttonStyle(.plain)
        if toolExpanded, !row.toolPreview.isEmpty {
          Text(row.toolPreview).font(.system(size: 14)).lineSpacing(7)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .foregroundStyle(Color(nsColor: TranscriptColors.muted))
      .padding(.vertical, 12)
      .padding(.bottom, 1)
      .overlay(alignment: .bottom) { Color(nsColor: TranscriptColors.border).frame(height: 1) }
      .padding(.horizontal, TranscriptStyle.horizontalInset)
      .padding(.vertical, 8)
    case .assistant, .user:
      MessageLayout(user: row.kind == .user) {
        VStack(alignment: .leading, spacing: 8) {
          if loadImages {
            ForEach(row.imageSources, id: \.self) { source in
              MessageImage(source: source)
            }
          }
          if !row.markdown.isEmpty {
            RichMarkdownText(
              rendered: markdownCache.render(row: row, loadImages: loadImages),
              expand: row.kind != .user)
          }
          if row.hasImagePlaceholder || (!loadImages && !row.imageSources.isEmpty) {
            AttachmentLabel("Image or attachment omitted")
          }
        }
        .padding(.horizontal, row.kind == .user ? TranscriptStyle.userHorizontalPadding : 0)
        .padding(.vertical, row.kind == .user ? TranscriptStyle.userVerticalPadding : 0)
        .background(
          row.kind == .user ? Color(nsColor: TranscriptColors.surfaceMuted) : Color.clear,
          in: RoundedRectangle(cornerRadius: 16))
      }
      .padding(.horizontal, TranscriptStyle.horizontalInset)
      .padding(.vertical, row.kind == .user ? 8 : 12)
    }
  }
}

@MainActor
private final class TranscriptMarkdownCache {
  private var rendered: [String: (String, NSAttributedString)] = [:]
  func render(row: ChatRow, loadImages: Bool) -> NSAttributedString {
    let key = "\(row.id):\(loadImages)"
    let source = row.markdown
    if let value = rendered[key], value.0 == source { return value.1 }
    let native = RichMarkdownRenderer.render(
      row.markdown, imagePolicy: loadImages ? .loadLocal : .omit)
    let value = native
    rendered[key] = (source, value)
    return value
  }
}

private struct RichMarkdownText: NSViewRepresentable {
  let rendered: NSAttributedString
  let expand: Bool

  func makeNSView(context: Context) -> TranscriptTextView { TranscriptTextView() }
  func updateNSView(_ view: TranscriptTextView, context: Context) {
    view.expandsToWidth = expand
    view.setContent(rendered)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: TranscriptTextView, context: Context) -> CGSize? {
    nsView.expandsToWidth = expand
    nsView.setContent(rendered)
    // SwiftUI probes the ideal width before proposing the bounded message width.
    // A zero ideal size makes a short message look horizontally flexible.
    let width = proposal.width.flatMap { $0.isFinite ? max(1, $0) : nil } ?? 1_000_000
    return nsView.size(fittingWidth: width)
  }
}

private struct MessageLayout: Layout {
  let user: Bool
  private func contentSize(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGSize {
    // An unspecified proposal asks for ideal size; do not turn it into a
    // one-point column and measure the entire transcript one character wide.
    let width = proposal.width.flatMap { width -> CGFloat? in
      guard width.isFinite else { return nil }
      return max(
        1,
        width * (user ? TranscriptStyle.userWidthFraction : TranscriptStyle.assistantWidthFraction))
    }
    return subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let size = contentSize(proposal, subviews)
    return CGSize(
      width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? size.width, height: size.height)
  }
  func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing { ViewSpacing() }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let size = contentSize(ProposedViewSize(bounds.size), subviews)
    subviews[0].place(
      at: CGPoint(x: user ? bounds.maxX - size.width : bounds.minX, y: bounds.minY),
      anchor: .topLeading, proposal: ProposedViewSize(size))
  }
}

private struct MessageImage: View {
  let source: String

  var body: some View {
    if let image = localImage {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: 300, maxHeight: 440)
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
      .frame(maxWidth: 300, maxHeight: 440)
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
        VStack(alignment: .leading, spacing: 4) {
          Text("Edited \(row.fileChanges.count) \(row.fileChanges.count == 1 ? "file" : "files")")
            .font(.system(size: 16, weight: .semibold))
          HStack(spacing: 8) {
            Text("+\(additions)").foregroundStyle(Color(nsColor: TranscriptColors.additions))
            Text("-\(deletions)").foregroundStyle(Color(nsColor: TranscriptColors.deletions))
          }
        }
        Spacer()
      }
      .padding(16)
      Divider()
      ForEach(expanded ? row.fileChanges : Array(row.fileChanges.prefix(3)), id: \.path) { file in
        HStack {
          Text(file.path).lineLimit(1).textSelection(.enabled)
          Spacer()
          Text("+\(file.additions)").foregroundStyle(Color(nsColor: TranscriptColors.additions))
          Text("-\(file.deletions)").foregroundStyle(Color(nsColor: TranscriptColors.deletions))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }
      if row.fileChanges.count > 3 {
        Divider()
        Button(expanded ? "Show less" : "Show \(row.fileChanges.count - 3) more files") {
          expanded.toggle()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(nsColor: TranscriptColors.surfaceMuted))
      }
    }
    .font(.system(size: 14))
    .background(Color(nsColor: TranscriptColors.surface))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: TranscriptColors.border)))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding(.horizontal, TranscriptStyle.horizontalInset)
    .padding(.vertical, 8)
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

// A fixed outer view lets List identify rows without evaluating each row's
// conditional body and materializing its Markdown before it is needed.
private struct LazyTranscriptRow: View {
  let loadImages: Bool
  let rows: ChatRows
  let index: Int
  let markdownCache: TranscriptMarkdownCache

  var body: some View {
    VStack(spacing: 0) {
      TranscriptRow(loadImages: loadImages, row: rows[index], markdownCache: markdownCache)
    }
  }
}

// Keep the SwiftUI bridge in this executable so the AppKit app does not link
// SwiftUI merely to use the shared AppKit glass control.
private struct TranscriptGlass: NSViewRepresentable {
  var titlebar = false
  func makeNSView(context: Context) -> TranscriptGlassView { TranscriptGlassView(titlebar: titlebar) }
  func updateNSView(_ nsView: TranscriptGlassView, context: Context) {}
}
