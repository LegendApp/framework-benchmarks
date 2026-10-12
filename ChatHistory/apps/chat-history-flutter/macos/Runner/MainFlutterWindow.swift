import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Native window material underneath Flutter's transparent sidebar. Transcript
    // and controls remain Flutter widgets, including their in-window blur.
    self.isOpaque = false
    self.backgroundColor = .clear
    flutterViewController.backgroundColor = .clear
    let material = NSVisualEffectView(frame: self.contentView?.bounds ?? .zero)
    material.material = .sidebar
    material.blendingMode = .behindWindow
    material.state = .active
    material.autoresizingMask = [.width, .height]
    let container = NSViewController()
    container.view = material
    container.addChild(flutterViewController)
    flutterViewController.view.frame = material.bounds
    flutterViewController.view.autoresizingMask = [.width, .height]
    material.addSubview(flutterViewController.view)
    self.contentViewController = container
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
