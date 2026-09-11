// Appended to a temporary copy of the production source by verify-appkit-layout.py.
@MainActor
private func runLayoutQA() {
  func check(_ condition: Bool, _ message: String) { if !condition { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) } }
  let controller = ContentViewController()
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 650), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  let root = NSView(frame: NSRect(x: 0, y: 0, width: 1040, height: 650))
  controller.view.frame = root.bounds
  controller.view.autoresizingMask = [.width, .height]
  root.addSubview(controller.view)
  controller.view.translatesAutoresizingMaskIntoConstraints = false
  NSLayoutConstraint.activate([controller.view.leadingAnchor.constraint(equalTo: root.leadingAnchor), controller.view.trailingAnchor.constraint(equalTo: root.trailingAnchor), controller.view.topAnchor.constraint(equalTo: root.topAnchor), controller.view.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
  window.contentView = root
  let contentWidth = controller.view.widthAnchor.constraint(equalToConstant: 1040)
  contentWidth.isActive = true
  controller.apply(settings: ChatHistorySettings(showPerformanceMetrics: false))
  window.orderFront(nil)
  let doc = try! openChatFile(provider: .codex, path: CommandLine.arguments[1])
  controller.show(document: doc, openedAt: ProcessInfo.processInfo.systemUptime * 1000) { _ in }
  func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  let table = descendants(controller.view).compactMap { $0 as? NSTableView }.first!
  var observations: [[String: Any]] = []
  for width in [1040.0, 560.0, 400.0, 1040.0] {
    contentWidth.constant = width
    window.contentMinSize = .zero
    window.setFrame(NSRect(x: 0, y: 0, width: width, height: 700), display: true, animate: false)
    controller.view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    for index in [doc.rows.count - 1, 0, doc.rows.count - 1] {
      table.scrollRowToVisible(index)
      table.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
      window.contentView?.layoutSubtreeIfNeeded()
      table.layoutSubtreeIfNeeded()
      check(abs(controller.view.bounds.width - width) < 1, "Container did not resize")
      let visibleCells = (0..<table.numberOfRows).filter { NSLocationInRange($0, table.rows(in: table.visibleRect)) }.compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: false) }
      let labels = visibleCells.flatMap(descendants).compactMap { $0 as? NSStackView }.flatMap { $0.arrangedSubviews }.compactMap { $0 as? NSTextField }.filter { $0.preferredMaxLayoutWidth > 0 }
      check(!labels.isEmpty, "No labels width \(width) row \(index)")
      for label in labels {
        let stack = label.superview!
        check(abs(label.preferredMaxLayoutWidth - min(820, stack.bounds.width)) < 1, "Preferred width \(label.preferredMaxLayoutWidth) stack \(stack.bounds.width) at container \(width)")
        check(label.alignmentRect(forFrame: label.frame).width <= stack.bounds.width + 1, "Text alignment rectangle exceeds its container")
        check(label.bounds.height.isFinite && label.bounds.height > 0, "Height invalid")
        check(label.frame.height + 1 >= label.intrinsicContentSize.height, "Row height clips text after resize")
      }
      let visible = table.rows(in: table.visibleRect)
      check(NSLocationInRange(index, visible), "Scroll target is not visible")
      observations.append(["containerWidth": width, "actualWidth": controller.view.bounds.width, "targetRow": index, "measuredLabels": labels.count, "preferredWidths": labels.map { $0.preferredMaxLayoutWidth }])
    }
  }
  print(String(data: try! JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
  window.orderOut(nil)
}
