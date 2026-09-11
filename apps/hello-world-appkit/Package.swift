// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "HelloWorldAppKit",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "HelloWorldAppKit", targets: ["HelloWorldAppKit"])],
  targets: [.executableTarget(name: "HelloWorldAppKit")]
)
