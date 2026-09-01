import AppKit
import Foundation

private struct LaunchResult: Codable {
  let launchStartedTimestampMs: Double
  let pid: Int32
}

guard CommandLine.arguments.count >= 2 else {
  FileHandle.standardError.write(Data("Usage: launch-app <bundle.app> [arguments...]\n".utf8))
  exit(2)
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.addsToRecentItems = false
configuration.createsNewApplicationInstance = true
configuration.arguments = Array(CommandLine.arguments.dropFirst(2))
configuration.environment = ProcessInfo.processInfo.environment
let launchStartedTimestampMs = Date().timeIntervalSince1970 * 1_000
NSWorkspace.shared.openApplication(
  at: URL(fileURLWithPath: CommandLine.arguments[1]),
  configuration: configuration
) { application, error in
  if let error {
    FileHandle.standardError.write(Data("Could not launch app: \(error.localizedDescription)\n".utf8))
    exit(3)
  }
  guard let application else {
    FileHandle.standardError.write(Data("LaunchServices returned no application\n".utf8))
    exit(4)
  }
  do {
    let result = LaunchResult(
      launchStartedTimestampMs: launchStartedTimestampMs,
      pid: application.processIdentifier)
    FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
  } catch {
    FileHandle.standardError.write(Data("Could not encode launch result: \(error)\n".utf8))
    exit(5)
  }
}
RunLoop.main.run()
