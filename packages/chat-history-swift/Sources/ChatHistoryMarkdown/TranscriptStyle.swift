import AppKit

/// apps/chat-history/src/TranscriptRow.tsx and ChatComposer.tsx in legend-apps.
public enum TranscriptStyle {
  // macOS 26 adds eight points around the floating native sidebar pane.
  public static var benchmarkSidebarPaneWidth: CGFloat {
    if #available(macOS 26, *) { return 252 }
    return 260
  }
  public static let horizontalInset: CGFloat = 20
  public static let userWidthFraction: CGFloat = 0.82
  public static let assistantWidthFraction: CGFloat = 0.92
  public static let userHorizontalPadding: CGFloat = 16
  public static let userVerticalPadding: CGFloat = 12
  public static let composerHeight: CGFloat = 88
  public static let bottomGap: CGFloat = 24
  public static func textWidth(columnWidth: CGFloat, user: Bool) -> CGFloat {
    max(
      1,
      (columnWidth - 2 * horizontalInset) * (user ? userWidthFraction : assistantWidthFraction)
        - (user ? 2 * userHorizontalPadding : 0))
  }
}

// The default Legend display theme, expressed as dynamic native colors.
@MainActor
public enum TranscriptColors {
  private static func color(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
      let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      return NSColor(
        srgbRed: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
  }
  public static let background = color(light: 0xf5f6f8, dark: 0x191a1b)
  public static let foreground = color(light: 0x111827, dark: 0xf5f5f5)
  public static let surfaceMuted = color(light: 0xf3f4f6, dark: 0x2d2e30)
  public static let inlineCodeForeground = color(light: 0x111827, dark: 0xeb5757)
  public static let inlineCodeBackground = color(light: 0xe5e7eb, dark: 0x2d2e30)
  public static let codeBackground = color(light: 0x111827, dark: 0x111213)
  public static let codeForeground = color(light: 0xf9fafb, dark: 0xf5f5f5)
}
