// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ChatHistoryAppKit",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "ChatHistoryAppKit", targets: ["ChatHistoryAppKit"])
  ],
  dependencies: [
    .package(path: "../../packages/chat-history-swift")
  ],
  targets: [
    .executableTarget(
      name: "ChatHistoryAppKit",
      dependencies: [
        .product(name: "ChatHistoryCore", package: "chat-history-swift"),
        .product(name: "ChatHistoryMarkdown", package: "chat-history-swift"),
      ]
    )
  ]
)
