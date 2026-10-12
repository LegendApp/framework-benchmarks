// swift-tools-version: 6.2
import PackageDescription
let package=Package(name:"CatalogProbe",platforms:[.macOS(.v14)],dependencies:[.package(path:"../../packages/chat-history-swift")],targets:[.executableTarget(name:"CatalogProbe",dependencies:[.product(name:"ChatHistoryCore",package:"chat-history-swift")])])
