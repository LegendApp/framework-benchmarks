// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "HelloWorldSwiftUI",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "HelloWorldSwiftUI", targets: ["HelloWorldSwiftUI"])],
  targets: [.executableTarget(name: "HelloWorldSwiftUI")]
)
