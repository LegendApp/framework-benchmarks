import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.setContentSize(NSSize(width: Double(ProcessInfo.processInfo.environment["CHAT_HISTORY_QA_WIDTH"] ?? "") ?? 1280, height: 720))
    self.contentMinSize = NSSize(width: 760, height: 520)
    self.title = "Legend Chat History — Flutter"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
