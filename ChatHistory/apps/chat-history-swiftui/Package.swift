// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ChatHistorySwiftUI",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "ChatHistorySwiftUI", targets: ["ChatHistorySwiftUI"])
  ],
  dependencies: [
    .package(path: "../../packages/chat-history-swift")
  ],
  targets: [
    .executableTarget(
      name: "ChatHistorySwiftUI",
      dependencies: [
        .product(name: "ChatHistoryCore", package: "chat-history-swift"),
        .product(name: "ChatHistoryMarkdown", package: "chat-history-swift"),
      ]
    )
  ]
)
