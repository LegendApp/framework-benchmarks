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
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
  ],
  targets: [
    .target(name: "ChatHistoryCore"),
    .target(
      name: "ChatHistoryMarkdown",
      dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
    .testTarget(name: "ChatHistoryCoreTests", dependencies: ["ChatHistoryCore"]),
    .testTarget(name: "ChatHistoryMarkdownTests", dependencies: ["ChatHistoryMarkdown"]),
  ]
)
