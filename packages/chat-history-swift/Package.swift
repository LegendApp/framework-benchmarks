// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ChatHistoryCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ChatHistoryCore", targets: ["ChatHistoryCore"]),
    .library(name: "ChatHistoryMarkdown", targets: ["ChatHistoryMarkdown"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
    .package(path: "Vendor/HighlighterSwift")
  ],
  targets: [
    .target(
      name: "ChatHistoryNative",
      exclude: ["PROVENANCE.json", "README.md"],
      cxxSettings: [.unsafeFlags(["-fobjc-arc"])],
      linkerSettings: [.linkedFramework("Foundation")]),
    .target(name: "ChatHistoryCore", dependencies: ["ChatHistoryNative"]),
    .target(
      name: "ChatHistoryMarkdown",
      dependencies: [.product(name: "Markdown", package: "swift-markdown"), .product(name: "Highlighter", package: "HighlighterSwift")]),
    .testTarget(name: "ChatHistoryCoreTests", dependencies: ["ChatHistoryCore"]),
    .testTarget(name: "ChatHistoryMarkdownTests", dependencies: ["ChatHistoryMarkdown"]),
  ],
  cxxLanguageStandard: .cxx20
)
