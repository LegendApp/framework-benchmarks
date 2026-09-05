import AppKit
import ChatHistoryCore
import ChatHistoryMarkdown

@main
@MainActor
enum ChatHistoryAppKitApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let root = ChatSplitViewController()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    window.title = "Legend Chat History"
    window.subtitle = "AppKit"
    window.minSize = NSSize(width: 640, height: 460)
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .shadow
    window.toolbarStyle = .unified
    window.contentViewController = root
    window.toolbar = root.makeToolbar()
    root.applyAppearance(to: window)
    window.setFrame(NSRect(x: 0, y: 0, width: 1_280, height: 720), display: false)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
    self.window = window
    DispatchQueue.main.async {
      ChatBenchmark.emitWindowShown()
      _ = RichMarkdownRenderer.render("Warmup")
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
private final class ChatSplitViewController: NSSplitViewController, NSToolbarDelegate {
  private static let toolbarIdentifier = NSToolbar.Identifier("ChatHistoryToolbar")
  private static let catalogItemIdentifier = NSToolbarItem.Identifier("ChatHistoryCatalog")
  private static let settingsItemIdentifier = NSToolbarItem.Identifier("ChatHistorySettings")
  private let sidebar = SidebarViewController()
  private let content = ContentViewController()
  private let catalogLabel = NSTextField(labelWithString: "Loading catalog…")
  private let benchmarkConfig = try? ChatBenchmark.load()
  private var benchmarkDiscoveryMs: Double?
  private let parserQueue = DispatchQueue(
    label: "so.legend.chathistory.appkit.parser", qos: .userInitiated)
  private var generation = 0
  private var selectedId: String?
  private var settings = ChatSettingsStore.load()

  override func viewDidLoad() {
    super.viewDidLoad()
    splitView.isVertical = true
    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
    sidebarItem.minimumThickness = 220
    sidebarItem.maximumThickness = 360
    sidebarItem.preferredThicknessFraction = 260 / 1_280
    addSplitViewItem(sidebarItem)
    addSplitViewItem(NSSplitViewItem(viewController: content))
    sidebar.onSelect = { [weak self] in self?.open($0) }
    if let benchmarkConfig {
      settings = ChatHistorySettings(
        loadImages: benchmarkConfig.loadImages,
        restoreSelection: false)
    }
    content.apply(settings: settings)
    Task { await loadCatalog() }
  }

  func makeToolbar() -> NSToolbar {
    loadViewIfNeeded()
    let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    return toolbar
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .toggleSidebar,
      .sidebarTrackingSeparator,
      .flexibleSpace,
      Self.catalogItemIdentifier,
      Self.settingsItemIdentifier,
    ]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .toggleSidebar,
      .sidebarTrackingSeparator,
      .flexibleSpace,
      Self.catalogItemIdentifier,
      Self.settingsItemIdentifier,
    ]
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch itemIdentifier {
    case .toggleSidebar:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Sidebar"
      item.paletteLabel = "Toggle Sidebar"
      item.toolTip = "Show or hide the sidebar"
      item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Sidebar")
      item.target = self
      item.action = #selector(toggleSidebar(_:))
      return item
    case .sidebarTrackingSeparator:
      return NSTrackingSeparatorToolbarItem(
        identifier: itemIdentifier,
        splitView: splitView,
        dividerIndex: 0)
    case Self.catalogItemIdentifier:
      catalogLabel.font = .systemFont(ofSize: 11)
      catalogLabel.textColor = .secondaryLabelColor
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Catalog timing"
      item.view = catalogLabel
      return item
    case Self.settingsItemIdentifier:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Settings"
      item.paletteLabel = "Settings"
      item.toolTip = "Settings"
      item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
      item.target = self
      item.action = #selector(settingsPressed)
      return item
    default:
      return nil
    }
  }

  @objc private func settingsPressed() { showSettings() }

  func applyAppearance(to window: NSWindow? = nil) {
    (window ?? view.window)?.appearance = settings.appearance.nsAppearance
  }

  private func loadCatalog(preferredId: String? = nil) async {
    let limit = benchmarkConfig == nil ? settings.recentChatLimit : Int.max
    let discoveryStartedAt = ProcessInfo.processInfo.systemUptime * 1_000
    let result = await Task.detached(priority: .userInitiated) { getRecentChats(limit: limit) }
      .value
    catalogLabel.stringValue = "catalog \(formatMs(result.nativeTotalMs)) ms"
    if let benchmarkConfig {
      benchmarkDiscoveryMs = ProcessInfo.processInfo.systemUptime * 1_000 - discoveryStartedAt
      let targets = benchmarkConfig.targets.compactMap { target in
        result.summaries.first { $0.id == target.id && $0.provider == target.provider }
      }
      guard targets.count == benchmarkConfig.targets.count else {
        content.showError("A pinned benchmark chat was not found during native history discovery")
        return
      }
      var visible = Array(result.summaries.prefix(settings.recentChatLimit))
      for target in targets where !visible.contains(where: { $0.id == target.id }) {
        visible.append(target)
      }
      sidebar.setSummaries(visible)
      sidebar.select(id: targets[0].id)
      open(targets[0], phase: .initial)
      return
    }
    sidebar.setSummaries(result.summaries)
    let restoredId = settings.restoreSelection ? preferredId ?? settings.selectedId : nil
    guard
      let initial = result.summaries.first(where: { $0.id == restoredId }) ?? result.summaries.first
    else {
      generation += 1
      selectedId = nil
      view.window?.title = "Legend Chat History"
      content.showEmptyCatalog()
      return
    }
    sidebar.select(id: initial.id)
    open(initial)
  }

  private func open(_ summary: ChatSummary, phase: ChatBenchmarkPhase? = nil) {
    guard selectedId != summary.id || (content.isEmpty && !content.isLoading) else { return }
    generation += 1
    let currentGeneration = generation
    selectedId = summary.id
    sidebar.select(id: summary.id)
    view.window?.title = summary.title
    if phase == nil && settings.restoreSelection {
      settings.selectedId = summary.id
      ChatSettingsStore.save(settings)
    }
    let openedAt = ProcessInfo.processInfo.systemUptime * 1_000
    content.showLoading()
    parserQueue.async { [weak self] in
      autoreleasepool {
        do {
          let document = try openChatFile(provider: summary.provider, path: summary.path)
          // Window presentation can defer default-mode work, so deliver results in common modes.
          RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
              guard let self, self.generation == currentGeneration else { return }
              self.content.show(document: document, openedAt: openedAt) { [weak self] durationMs in
                self?.contentReady(document: document, durationMs: durationMs, phase: phase)
              }
            }
          }
        } catch {
          let message = error.localizedDescription
          RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
              guard let self, self.generation == currentGeneration else { return }
              self.content.showError(message)
            }
          }
        }
      }
    }
  }

  private func contentReady(
    document: ChatDocument,
    durationMs: Double,
    phase: ChatBenchmarkPhase?
  ) {
    guard let phase else { return }
    ChatBenchmark.emit(
      ChatBenchmarkContentReadyEvent(
        discoveryMs: phase == .initial ? benchmarkDiscoveryMs : nil,
        durationMs: durationMs,
        document: document,
        phase: phase))
    ChatBenchmark.emitContentDigest(document: document, phase: phase)
    if phase == .initial, let benchmarkConfig, benchmarkConfig.targets.count == 2,
      let secondary = sidebar.summary(id: benchmarkConfig.targets[1].id)
    {
      Task {
        try? await Task.sleep(for: .milliseconds(Int64(benchmarkConfig.switchDelayMs)))
        open(secondary, phase: .switch)
      }
    }
  }

  private func showSettings() {
    guard let host = view.window, host.attachedSheet == nil else { return }
    let controller = SettingsViewController(settings: settings)
    let sheet = NSWindow(contentViewController: controller)
    sheet.title = "Settings"
    sheet.styleMask = [.titled]
    controller.onCancel = { [weak host, weak sheet] in
      if let sheet { host?.endSheet(sheet) }
    }
    controller.onSave = { [weak self, weak host, weak sheet] value in
      guard let self else { return }
      if let sheet { host?.endSheet(sheet) }
      let previousLimit = self.settings.recentChatLimit
      var normalized = value
      normalized.selectedId = normalized.restoreSelection ? self.selectedId : nil
      normalized.normalize()
      self.settings = normalized
      ChatSettingsStore.save(normalized)
      self.applyAppearance()
      self.content.apply(settings: normalized)
      if normalized.recentChatLimit != previousLimit {
        Task { await self.loadCatalog(preferredId: self.selectedId) }
      }
    }
    host.beginSheet(sheet)
  }
}

@MainActor
private final class SidebarViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate
{
  enum Item {
    case header(ChatProvider)
    case spacer
    case summary(ChatSummary)
  }
  var onSelect: ((ChatSummary) -> Void)?
  private var items: [Item] = [.header(.codex), .spacer, .header(.claude)]
  private var lastSelectedRow = -1
  private var suppressSelection = false
  private let tableView = NSTableView()
  private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }()

  override func loadView() {
    let root = NSVisualEffectView()
    root.material = .sidebar
    root.blendingMode = .behindWindow
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.dataSource = self
    tableView.delegate = self
    tableView.focusRingType = .none
    tableView.intercellSpacing = .zero
    tableView.selectionHighlightStyle = .regular
    let scroll = NSScrollView()
    scroll.documentView = tableView
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    view = root
  }

  func setSummaries(_ summaries: [ChatSummary]) {
    items = [.header(.codex)]
    items += summaries.filter { $0.provider == .codex }.map(Item.summary)
    items.append(.spacer)
    items.append(.header(.claude))
    items += summaries.filter { $0.provider == .claude }.map(Item.summary)
    tableView.reloadData()
  }

  func summary(id: String) -> ChatSummary? {
    items.lazy.compactMap { item -> ChatSummary? in
      if case .summary(let summary) = item { return summary }
      return nil
    }.first { $0.id == id }
  }

  func select(id: String) {
    guard
      let row = items.firstIndex(where: {
        if case .summary(let summary) = $0 { return summary.id == id }
        return false
      })
    else { return }
    suppressSelection = true
    let previousRow = lastSelectedRow
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    tableView.scrollRowToVisible(row)
    lastSelectedRow = row
    reloadSelectionRows(previousRow, row)
    suppressSelection = false
  }

  func numberOfRows(in tableView: NSTableView) -> Int { items.count }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    switch items[row] {
    case .header: return 40
    case .spacer: return 12
    case .summary: return 34
    }
  }
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if case .summary = items[row] { return true }
    return false
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !suppressSelection else { return }
    let row = tableView.selectedRow
    guard row >= 0, case .summary(let summary) = items[row] else { return }
    guard row != lastSelectedRow else { return }
    let previousRow = lastSelectedRow
    lastSelectedRow = row
    reloadSelectionRows(previousRow, row)
    onSelect?(summary)
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    if case .summary = items[row] { return SidebarRowView() }
    return NSTableRowView()
  }

  func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
    switch items[row] {
    case .header(let provider):
      let identifier = NSUserInterfaceItemIdentifier("header")
      let cell =
        tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        ?? headerCell(identifier)
      cell.textField?.stringValue = provider == .codex ? "Codex" : "Claude"
      return cell
    case .spacer:
      return NSView()
    case .summary(let summary):
      let identifier = NSUserInterfaceItemIdentifier("summary")
      let cell =
        tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarSummaryCell
        ?? SidebarSummaryCell(identifier: identifier)
      cell.configure(
        title: summary.title,
        date: relativeDate(summary.updatedAt),
        selected: tableView.selectedRow == row)
      return cell
    }
  }

  private func headerCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 13, weight: .bold)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.textField = label
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  private func reloadSelectionRows(_ previous: Int, _ current: Int) {
    var rows = IndexSet(integer: current)
    if previous >= 0 { rows.insert(previous) }
    tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
  }

  private func relativeDate(_ timestamp: Double) -> String {
    let elapsedMinutes = max(0, Int((Date().timeIntervalSince1970 - timestamp / 1_000) / 60))
    if elapsedMinutes < 1 { return "now" }
    if elapsedMinutes < 60 { return "\(elapsedMinutes)m" }
    let hours = elapsedMinutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days < 7 { return "\(days)d" }
    return dateFormatter.string(from: Date(timeIntervalSince1970: timestamp / 1_000))
  }
}

@MainActor
private final class SidebarRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    NSColor.controlAccentColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 8, yRadius: 8).fill()
  }
}

@MainActor
private final class SidebarSummaryCell: NSTableCellView {
  private let titleLabel = NSTextField(labelWithString: "")
  private let dateLabel = NSTextField(labelWithString: "")

  init(identifier: NSUserInterfaceItemIdentifier) {
    super.init(frame: .zero)
    self.identifier = identifier
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    dateLabel.font = .systemFont(ofSize: 11)
    dateLabel.textColor = .secondaryLabelColor
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    dateLabel.setContentHuggingPriority(.required, for: .horizontal)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    dateLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(titleLabel)
    addSubview(dateLabel)
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      dateLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
      dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      dateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  func configure(title: String, date: String, selected: Bool) {
    titleLabel.stringValue = title
    dateLabel.stringValue = date
    titleLabel.textColor = selected ? .white : .labelColor
    dateLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor
  }
}

@MainActor
private final class ContentViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate
{
  var isEmpty: Bool { document == nil }
  private(set) var isLoading = false
  private var document: ChatDocument?
  private var expandedRows = Set<String>()
  private var firstPaintMs: Double?
  private var renderedMarkdown: [String: NSAttributedString] = [:]
  private var metricsHeight: NSLayoutConstraint!
  private var settings = ChatHistorySettings()
  private let emptyLabel = NSTextField(labelWithString: "Scanning recent chats…")
  private let metricsLabel = NSTextField(labelWithString: "")
  private let scroll = NSScrollView()
  private let tableView = NSTableView()

  override func loadView() {
    let root = NSView()
    metricsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    metricsLabel.backgroundColor = .controlBackgroundColor
    metricsLabel.drawsBackground = true
    metricsLabel.isHidden = true
    metricsLabel.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("transcript"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.backgroundColor = .textBackgroundColor
    tableView.dataSource = self
    tableView.delegate = self
    tableView.intercellSpacing = .zero
    tableView.selectionHighlightStyle = .none
    tableView.rowHeight = 96
    tableView.usesAutomaticRowHeights = true
    scroll.documentView = tableView
    scroll.hasVerticalScroller = true
    scroll.isHidden = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.textColor = .secondaryLabelColor
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    for child in [metricsLabel, scroll, emptyLabel] { root.addSubview(child) }
    metricsHeight = metricsLabel.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      metricsLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      metricsLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      metricsLabel.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
      metricsHeight,
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: metricsLabel.bottomAnchor),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
    ])
    view = root
  }

  func apply(settings: ChatHistorySettings) {
    self.settings = settings
    renderedMarkdown.removeAll(keepingCapacity: true)
    updateMetricsVisibility()
    tableView.reloadData()
  }

  func showLoading() {
    isLoading = true
    document = nil
    expandedRows.removeAll()
    renderedMarkdown.removeAll(keepingCapacity: true)
    firstPaintMs = nil
    updateMetricsVisibility()
    scroll.isHidden = true
    emptyLabel.isHidden = false
    emptyLabel.textColor = .secondaryLabelColor
    emptyLabel.stringValue = "Loading and parsing natively…"
    tableView.reloadData()
  }

  func showError(_ message: String) {
    isLoading = false
    document = nil
    updateMetricsVisibility()
    scroll.isHidden = true
    emptyLabel.isHidden = false
    emptyLabel.textColor = .systemRed
    emptyLabel.stringValue = message
  }

  func showEmptyCatalog() {
    isLoading = false
    document = nil
    expandedRows.removeAll()
    renderedMarkdown.removeAll(keepingCapacity: true)
    firstPaintMs = nil
    updateMetricsVisibility()
    scroll.isHidden = true
    emptyLabel.isHidden = false
    emptyLabel.textColor = .secondaryLabelColor
    emptyLabel.stringValue = "No local Codex or Claude transcripts found."
    tableView.reloadData()
  }

  func show(
    document: ChatDocument,
    openedAt: Double,
    onReady: @escaping @MainActor @Sendable (Double) -> Void
  ) {
    isLoading = false
    self.document = document
    firstPaintMs = nil
    expandedRows.removeAll()
    renderedMarkdown.removeAll(keepingCapacity: true)
    emptyLabel.isHidden = true
    scroll.isHidden = false
    updateMetricsVisibility()
    updateMetrics()
    tableView.reloadData()
    // Keep the first layout moving while AppKit presents the window in a non-default mode.
    RunLoop.main.perform(inModes: [.common]) { [weak self] in
      MainActor.assumeIsolated {
        self?.settleVisibleLayout(document: document, openedAt: openedAt, onReady: onReady)
      }
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { document?.rows.count ?? 0 }

  func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
    guard let item = document?.rows[row] else { return nil }
    let identifier = NSUserInterfaceItemIdentifier("transcript-row")
    let cell =
      tableView.makeView(withIdentifier: identifier, owner: self) as? TranscriptCell
      ?? TranscriptCell(identifier: identifier)
    let markdown = item.markdown.isEmpty
      ? nil
      : renderedMarkdown[item.id]
        ?? RichMarkdownRenderer.render(
          item.markdown, imagePolicy: settings.loadImages ? .loadLocal : .omit)
    if let markdown { renderedMarkdown[item.id] = markdown }
    cell.configure(
      with: item,
      markdown: markdown,
      loadImages: settings.loadImages,
      expanded: expandedRows.contains(item.id)
    ) { [weak self] in
      guard let self else { return }
      if self.expandedRows.contains(item.id) {
        self.expandedRows.remove(item.id)
      } else {
        self.expandedRows.insert(item.id)
      }
      let indexes = IndexSet(integer: row)
      self.tableView.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: 0))
      self.tableView.noteHeightOfRows(withIndexesChanged: indexes)
    }
    return cell
  }

  private func settleVisibleLayout(
    document: ChatDocument,
    openedAt: Double,
    onReady: @escaping @MainActor @Sendable (Double) -> Void
  ) {
    guard self.document?.path == document.path else { return }
    if !document.rows.isEmpty { tableView.scrollRowToVisible(document.rows.count - 1) }
    tableView.layoutSubtreeIfNeeded()
    view.window?.displayIfNeeded()
    let durationMs = ProcessInfo.processInfo.systemUptime * 1_000 - openedAt
    firstPaintMs = durationMs
    updateMetrics()
    onReady(durationMs)
  }

  private func updateMetricsVisibility() {
    let visible = document != nil && settings.showPerformanceMetrics
    metricsLabel.isHidden = !visible
    metricsHeight.constant = visible ? 34 : 0
  }

  private func updateMetrics() {
    guard let document else { return }
    let paint = firstPaintMs.map { "paint \(formatMs($0)) ms" } ?? "paint pending"
    metricsLabel.stringValue =
      "  \(formatBytes(document.sourceBytes))    \(document.recordCount) records    \(document.rows.count) rows    load \(formatMs(document.timing.loadMs)) ms    scan \(formatMs(document.timing.scanMs)) ms    parse \(formatMs(document.timing.parseMs)) ms    bridge 0.00 ms    \(paint)"
  }
}

@MainActor
private final class TranscriptCell: NSTableCellView {
  private let stack = NSStackView()
  private var leadingConstraint: NSLayoutConstraint!
  private var toggle: (() -> Void)?

  init(identifier: NSUserInterfaceItemIdentifier) {
    super.init(frame: .zero)
    self.identifier = identifier
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    leadingConstraint = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22)
    NSLayoutConstraint.activate([
      leadingConstraint,
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  func configure(
    with row: ChatRow,
    markdown: NSAttributedString?,
    loadImages: Bool,
    expanded: Bool,
    onToggle: @escaping () -> Void
  ) {
    reset()
    toggle = onToggle
    switch row.kind {
    case .assistant, .user:
      leadingConstraint.constant = row.kind == .user ? 100 : 22
      if loadImages {
        for source in row.imageSources { addImage(source) }
      }
      if let markdown {
        stack.addArrangedSubview(markdownLabel(markdown, user: row.kind == .user))
      }
      if row.hasImagePlaceholder || (!loadImages && !row.imageSources.isEmpty) {
        stack.addArrangedSubview(attachmentLabel("Image or attachment omitted"))
      }
    case .tool:
      let status = row.toolStatus == .failed ? "  Failed" : ""
      let button = disclosureButton("\(expanded ? "▾" : "▸") \(row.toolName)\(status)")
      button.contentTintColor = row.toolStatus == .failed ? .systemRed : .secondaryLabelColor
      stack.addArrangedSubview(button)
      if expanded && !row.toolPreview.isEmpty {
        stack.addArrangedSubview(detailLabel(row.toolPreview))
      }
    case .files:
      addFileChanges(row, expanded: expanded)
    }
  }

  private func reset() {
    toggle = nil
    leadingConstraint.constant = 22
    for view in stack.arrangedSubviews {
      stack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
  }

  private func markdownLabel(_ markdown: NSAttributedString, user: Bool) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: "")
    label.isSelectable = true
    label.allowsEditingTextAttributes = true
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.attributedStringValue = markdown
    if user {
      label.drawsBackground = true
      label.backgroundColor = .controlBackgroundColor
      label.wantsLayer = true
      label.layer?.cornerRadius = 12
    }
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 820).isActive = true
    return label
  }

  private func addImage(_ source: String) {
    let imageView = MessageImageView()
    imageView.imageAlignment = .alignCenter
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 12
    imageView.layer?.masksToBounds = true
    imageView.translatesAutoresizingMaskIntoConstraints = false
    let preferredWidth = imageView.widthAnchor.constraint(equalToConstant: 560)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      preferredWidth,
      imageView.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
      imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 4 / 7),
    ])
    imageView.load(source: source)
    stack.addArrangedSubview(imageView)
  }

  private func addFileChanges(_ row: ChatRow, expanded: Bool) {
    let additions = row.fileChanges.reduce(0) { $0 + $1.additions }
    let deletions = row.fileChanges.reduce(0) { $0 + $1.deletions }
    let noun = row.fileChanges.count == 1 ? "file" : "files"
    let heading = NSTextField(
      labelWithString: "Edited \(row.fileChanges.count) \(noun)    +\(additions)    −\(deletions)")
    heading.font = .systemFont(ofSize: 13, weight: .semibold)
    stack.addArrangedSubview(heading)
    let visibleFiles = expanded ? row.fileChanges : Array(row.fileChanges.prefix(3))
    for file in visibleFiles {
      let line = NSTextField(
        labelWithString: "\(file.path)    +\(file.additions)    −\(file.deletions)")
      line.isSelectable = true
      line.lineBreakMode = .byTruncatingMiddle
      line.textColor = .secondaryLabelColor
      line.widthAnchor.constraint(lessThanOrEqualToConstant: 820).isActive = true
      stack.addArrangedSubview(line)
    }
    if row.fileChanges.count > 3 {
      let title = expanded ? "Show less" : "Show \(row.fileChanges.count - 3) more files"
      stack.addArrangedSubview(disclosureButton(title))
    }
  }

  private func disclosureButton(_ title: String) -> NSButton {
    let button = NSButton(title: title, target: self, action: #selector(togglePressed))
    button.bezelStyle = .inline
    button.isBordered = false
    button.font = .systemFont(ofSize: 13, weight: .medium)
    button.setButtonType(.momentaryPushIn)
    return button
  }

  private func detailLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.isSelectable = true
    label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    label.textColor = .secondaryLabelColor
    label.drawsBackground = true
    label.backgroundColor = .controlBackgroundColor
    label.wantsLayer = true
    label.layer?.cornerRadius = 7
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 820).isActive = true
    return label
  }

  private func attachmentLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    label.wantsLayer = true
    label.layer?.borderWidth = 1
    label.layer?.borderColor = NSColor.separatorColor.cgColor
    label.layer?.cornerRadius = 7
    return label
  }

  @objc private func togglePressed() { toggle?() }
}

@MainActor
private final class MessageImageView: NSImageView {
  private var representedSource = ""
  private var task: Task<Void, Never>?

  func load(source: String) {
    representedSource = source
    task?.cancel()
    image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Loading image")
    if let local = localImage(source) {
      image = local
      return
    }
    guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased()) else {
      image = NSImage(
        systemSymbolName: "photo.badge.exclamationmark",
        accessibilityDescription: "Image unavailable")
      return
    }
    task = Task { [weak self] in
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard !Task.isCancelled, self?.representedSource == source else { return }
        self?.image = NSImage(data: data) ?? Self.unavailableImage
      } catch {
        guard !Task.isCancelled, self?.representedSource == source else { return }
        self?.image = Self.unavailableImage
      }
    }
  }

  private func localImage(_ source: String) -> NSImage? {
    if source.hasPrefix("file://"), let url = URL(string: source) {
      return NSImage(contentsOf: url)
    }
    return source.contains("://") ? nil : NSImage(contentsOfFile: source)
  }

  private static var unavailableImage: NSImage? {
    NSImage(
      systemSymbolName: "photo.badge.exclamationmark",
      accessibilityDescription: "Image unavailable")
  }
}

@MainActor
private final class SettingsViewController: NSViewController {
  var onCancel: (() -> Void)?
  var onSave: ((ChatHistorySettings) -> Void)?
  private let appearance = NSPopUpButton()
  private let recentChats = NSPopUpButton()
  private let restoreSelection = NSButton(
    checkboxWithTitle: "Restore the last selected chat", target: nil, action: nil)
  private let loadImages = NSButton(
    checkboxWithTitle: "Load attached images", target: nil, action: nil)
  private let showMetrics = NSButton(
    checkboxWithTitle: "Show performance metrics", target: nil, action: nil)
  private var settings: ChatHistorySettings

  init(settings: ChatHistorySettings) {
    self.settings = settings
    super.init(nibName: nil, bundle: nil)
    preferredContentSize = NSSize(width: 440, height: 330)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func loadView() {
    let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
    let title = NSTextField(labelWithString: "Settings")
    title.font = .systemFont(ofSize: 22, weight: .bold)
    appearance.addItems(withTitles: ["System", "Light", "Dark"])
    appearance.selectItem(at: ChatAppearance.allCases.firstIndex(of: settings.appearance) ?? 0)
    recentChats.addItems(withTitles: ["20", "50", "100"])
    recentChats.selectItem(withTitle: String(settings.recentChatLimit))
    restoreSelection.state = settings.restoreSelection ? .on : .off
    loadImages.state = settings.loadImages ? .on : .off
    showMetrics.state = settings.showPerformanceMetrics ? .on : .off

    let form = NSStackView(views: [
      formRow(label: "Appearance", control: appearance),
      formRow(label: "Recent chats", control: recentChats),
      restoreSelection,
      loadImages,
      showMetrics,
    ])
    form.orientation = .vertical
    form.alignment = .leading
    form.spacing = 14
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
    let save = NSButton(title: "Save", target: self, action: #selector(savePressed))
    save.keyEquivalent = "\r"
    let buttons = NSStackView(views: [cancel, save])
    buttons.orientation = .horizontal
    buttons.spacing = 8
    for child in [title, form, buttons] {
      child.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(child)
    }
    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
      form.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      form.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
      form.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
      buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
    ])
    view = root
  }

  private func formRow(label: String, control: NSView) -> NSView {
    let labelView = NSTextField(labelWithString: label)
    labelView.widthAnchor.constraint(equalToConstant: 130).isActive = true
    let row = NSStackView(views: [labelView, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    return row
  }

  @objc private func cancelPressed() { onCancel?() }

  @objc private func savePressed() {
    settings.appearance = ChatAppearance.allCases[appearance.indexOfSelectedItem]
    settings.recentChatLimit = Int(recentChats.titleOfSelectedItem ?? "20") ?? 20
    settings.restoreSelection = restoreSelection.state == .on
    settings.loadImages = loadImages.state == .on
    settings.showPerformanceMetrics = showMetrics.state == .on
    onSave?(settings)
  }
}

extension ChatAppearance {
  fileprivate var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}

private func formatMs(_ value: Double) -> String { String(format: "%.2f", value) }

private func formatBytes(_ bytes: Int) -> String {
  String(format: "%.1f KB", Double(bytes) / 1_024)
}
