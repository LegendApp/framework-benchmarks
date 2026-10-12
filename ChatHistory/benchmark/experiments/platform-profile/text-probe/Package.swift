// swift-tools-version: 6.2
import PackageDescription
let package=Package(name:"TextProbe",platforms:[.macOS(.v14)],dependencies:[.package(path:"../../packages/chat-history-swift")],targets:[.executableTarget(name:"TextProbe",dependencies:[.product(name:"ChatHistoryCore",package:"chat-history-swift"),.product(name:"ChatHistoryMarkdown",package:"chat-history-swift")])])
