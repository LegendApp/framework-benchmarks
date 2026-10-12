import AppKit

/// Matches legend-apps' GlassSurface: real macOS 26 glass, with a regular-material
/// fallback on older systems. Content lives inside the glass contentView.
@MainActor
public final class TranscriptGlassView: NSView {
  public let content = NSView()
  private let overlay = NSView()
  private let effect: NSView
  private let titlebar: Bool
  public init(titlebar: Bool = false) {
    self.titlebar = titlebar
    if #available(macOS 26, *) {
      let glass = NSGlassEffectView()
      glass.style = .regular
      glass.cornerRadius = titlebar ? 0 : 26
      if !titlebar { glass.contentView = content }
      effect = glass
    } else {
      let material = NSVisualEffectView()
      material.material = titlebar ? .headerView : .contentBackground
      material.blendingMode = .withinWindow
      material.state = .active
      effect = material
    }
    super.init(frame: .zero)
    wantsLayer = true
    addSubview(effect)
    if titlebar {
      overlay.wantsLayer = true
      addSubview(overlay)
    }
    if content.superview == nil && !titlebar { addSubview(content) }
    if !titlebar {
      layer?.cornerRadius = 26
      layer?.borderWidth = 1
      layer?.shadowColor = NSColor.black.cgColor
      layer?.shadowOpacity = 0.22
      layer?.shadowRadius = 24
      layer?.shadowOffset = NSSize(width: 0, height: -10)
    } else {
      layer?.masksToBounds = true
    }
    updateColors()
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  public override func hitTest(_ point: NSPoint) -> NSView? {
    titlebar ? nil : super.hitTest(point)
  }
  public override func layout() {
    super.layout()
    // RN overscans the rectangular titlebar glass to hide its edge lens.
    effect.frame = titlebar
      ? NSRect(x: -48, y: 0, width: bounds.width + 96, height: bounds.height + 48)
      : bounds
    content.frame = bounds
    overlay.frame = bounds
  }
  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }
  private func updateColors() {
    let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
      glass.tintColor = titlebar ? nil : (dark
        ? NSColor(srgbRed: 32/255, green: 33/255, blue: 36/255, alpha: 0.4)
        : NSColor.white.withAlphaComponent(112/255))
    }
    layer?.borderColor = titlebar ? nil : TranscriptColors.border.cgColor
    overlay.layer?.backgroundColor = TranscriptColors.background.withAlphaComponent(dark ? 0 : 0.1).cgColor
    needsDisplay = true
  }
}
